using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Un episodio, o un blocco di episodi usciti insieme, prima di guardare chi
/// chiede (spec M §7.3). LastEpisodeNumber c'è solo per un blocco, e allora
/// EpisodeTitle no.
/// </summary>
public sealed record UpcomingEpisodeGroup(
    int SonarrSeriesId,
    string SeriesName,
    int SeasonNumber,
    int EpisodeNumber,
    int? LastEpisodeNumber,
    string? EpisodeTitle,
    DateTimeOffset AirDateUtc,
    int? TvdbId,
    int? TmdbId,
    string? ImdbId,
    string? PosterUrl,
    string? BackdropUrl)
{
    /// <summary>Le serie di Jellyfin con gli stessi id esterni; per ogni utente vale la prima che vede.</summary>
    public IReadOnlyList<Guid> LibrarySeriesIds { get; init; } = [];
}

/// <summary>Un film in arrivo (spec M §7.3).</summary>
public sealed record UpcomingMovie(
    string Title,
    int? Year,
    int TmdbId,
    DateTimeOffset DigitalRelease,
    string? PosterUrl,
    string? BackdropUrl);

/// <summary>
/// Dai calendari di Sonarr e Radarr alle uscite della Home: filtri, blocchi
/// di episodi, immagini pubbliche e serie della libreria. I periodi vanno da
/// <c>from</c> compreso a <c>to</c> escluso (decisione 3 del piano 19a).
/// </summary>
public static class UpcomingBuilder
{
    private const string PosterType = "poster";
    private const string BackdropType = "fanart";

    /// <summary>
    /// Gli episodi non ancora scaricati del periodo, con una serie che ha un
    /// nome. Episodi della stessa serie e stagione, con numeri consecutivi e
    /// lo stesso airDateUtc (le uscite in blocco), diventano una voce sola.
    /// In ordine di uscita, poi di serie.
    /// </summary>
    public static IReadOnlyList<UpcomingEpisodeGroup> Episodes(
        IEnumerable<SonarrEpisode?> episodes, DateTimeOffset from, DateTimeOffset to)
    {
        var groups = new List<UpcomingEpisodeGroup>();
        UpcomingEpisodeGroup? current = null;
        foreach (var episode in episodes.OfType<SonarrEpisode>()
                     .Where(e => !e.HasFile
                                 && !string.IsNullOrWhiteSpace(e.Series?.Title)
                                 && e.AirDateUtc is { } at && at >= from && at < to)
                     .OrderBy(e => e.AirDateUtc)
                     .ThenBy(e => e.SeriesId)
                     .ThenBy(e => e.SeasonNumber)
                     .ThenBy(e => e.EpisodeNumber))
        {
            var at = episode.AirDateUtc!.Value;
            if (current is not null
                && current.SonarrSeriesId == episode.SeriesId
                && current.SeasonNumber == episode.SeasonNumber
                && current.AirDateUtc == at
                && (current.LastEpisodeNumber ?? current.EpisodeNumber) + 1 == episode.EpisodeNumber)
            {
                current = current with { LastEpisodeNumber = episode.EpisodeNumber, EpisodeTitle = null };
                groups[^1] = current;
                continue;
            }

            var series = episode.Series!;
            current = new UpcomingEpisodeGroup(
                episode.SeriesId,
                series.Title!.Trim(),
                episode.SeasonNumber,
                episode.EpisodeNumber,
                null,
                Text(episode.Title),
                at,
                Positive(series.TvdbId),
                Positive(series.TmdbId),
                Text(series.ImdbId),
                Image(series.Images, PosterType),
                Image(series.Images, BackdropType));
            groups.Add(current);
        }

        return groups
            .OrderBy(g => g.AirDateUtc)
            .ThenBy(g => g.SeriesName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(g => g.SeasonNumber)
            .ThenBy(g => g.EpisodeNumber)
            .ToList();
    }

    /// <summary>
    /// I film non ancora scaricati con l'uscita digitale nel periodo, un id
    /// TMDB e un titolo; in ordine di uscita, poi di titolo.
    /// </summary>
    public static IReadOnlyList<UpcomingMovie> Movies(IEnumerable<RadarrMovie?> movies, DateTimeOffset from, DateTimeOffset to) =>
        movies.OfType<RadarrMovie>()
            .Where(m => !m.HasFile
                        && m.TmdbId > 0
                        && !string.IsNullOrWhiteSpace(m.Title)
                        && m.DigitalRelease is { } at && at >= from && at < to)
            .Select(m => new UpcomingMovie(
                m.Title!.Trim(),
                Positive(m.Year),
                m.TmdbId,
                m.DigitalRelease!.Value,
                Image(m.Images, PosterType),
                Image(m.Images, BackdropType)))
            .OrderBy(m => m.DigitalRelease)
            .ThenBy(m => m.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();

    /// <summary>Ogni voce con le serie della libreria che hanno lo stesso id TVDB, TMDB o IMDb.</summary>
    public static IReadOnlyList<UpcomingEpisodeGroup> MatchSeries(
        IReadOnlyList<UpcomingEpisodeGroup> groups, IEnumerable<LibrarySeries> library)
    {
        var all = library.ToList();
        return groups
            .Select(group => group with
            {
                LibrarySeriesIds = all.Where(series => Matches(group, series)).Select(series => series.Id).Distinct().ToList(),
            })
            .ToList();
    }

    /// <summary>
    /// Il remoteUrl del tipo chiesto, solo se è un indirizzo http(s) completo:
    /// mai i percorsi locali di Sonarr (/MediaCover/…), che vogliono la chiave.
    /// </summary>
    internal static string? Image(IEnumerable<ArrImage?>? images, string coverType) =>
        images?.OfType<ArrImage>()
            .Where(image => string.Equals(image.CoverType, coverType, StringComparison.OrdinalIgnoreCase))
            .Select(image => image.RemoteUrl?.Trim())
            .FirstOrDefault(url => Uri.TryCreate(url, UriKind.Absolute, out var uri)
                                   && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp));

    private static bool Matches(UpcomingEpisodeGroup group, LibrarySeries series) =>
        (group.TvdbId is { } tvdb && Same(series.TvdbId, tvdb.ToString(CultureInfo.InvariantCulture)))
        || (group.TmdbId is { } tmdb && Same(series.TmdbId, tmdb.ToString(CultureInfo.InvariantCulture)))
        || (group.ImdbId is { } imdb && Same(series.ImdbId, imdb));

    private static bool Same(string? value, string expected) =>
        value is not null && string.Equals(value.Trim(), expected, StringComparison.OrdinalIgnoreCase);

    private static int? Positive(int value) => value > 0 ? value : null;

    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
