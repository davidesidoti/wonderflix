using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Il calendario delle uscite di un periodo (spec S §6.1). Sonarr e Radarr si
/// leggono in parallelo, ognuno con la sua cache per periodo (le voci già
/// costruite, scaricate comprese); la libreria visibile si sceglie per ogni utente.
/// </summary>
public sealed class CalendarService(
    IArrClient client,
    IArrSettings settings,
    ISeriesIndex index,
    ILibraryAccess library,
    TimeProvider time,
    ILogger<CalendarService> logger)
{
    /// <summary>Giorni massimi di un periodo (<c>end</c> escluso).</summary>
    public const int MaxDays = 42;

    /// <summary>Periodi tenuti in cache, per servizio.</summary>
    public const int MaxCachedPeriods = 6;

    /// <summary>Un giorno in più per lato: i fusi orari spostano l'uscita sul giorno accanto.</summary>
    public static readonly TimeSpan Margin = TimeSpan.FromDays(1);

    private readonly ArrReadCache<IReadOnlyList<UpcomingEpisodeGroup>> _series = new(time, MaxCachedPeriods, logger);
    private readonly ArrReadCache<IReadOnlyList<UpcomingMovie>> _movies = new(time, MaxCachedPeriods, logger);

    /// <summary><c>end</c> dopo <c>start</c> e al più <see cref="MaxDays"/> giorni.</summary>
    public static bool IsValidPeriod(DateOnly start, DateOnly end) =>
        // Ai due estremi del calendario il margine di un giorno non e' rappresentabile.
        start > DateOnly.MinValue && end < DateOnly.MaxValue && end > start &&end.DayNumber - start.DayNumber <= MaxDays;

    /// <summary>Solo con un periodo valido.</summary>
    public async Task<CalendarResponse> GetAsync(
        Guid userId, DateOnly start, DateOnly end, CancellationToken cancellationToken)
    {
        var from = new DateTimeOffset(start.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero) - Margin;
        var to = new DateTimeOffset(end.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero) + Margin;
        var period = $"{start:yyyy-MM-dd}\n{end:yyyy-MM-dd}";

        var series = ReadAsync(
            settings.Sonarr,
            _series,
            period,
            async () => UpcomingBuilder.MatchSeries(
                UpcomingBuilder.Episodes(
                    await client.GetEpisodesAsync(from, to, CancellationToken.None).ConfigureAwait(false),
                    from,
                    to,
                    includeDownloaded: true),
                ReadLibrary(index.GetSeries)));
        var movies = ReadAsync(
            settings.Radarr,
            _movies,
            period,
            async () => UpcomingBuilder.MatchMovies(
                UpcomingBuilder.Movies(
                    await client.GetMoviesAsync(from, to, CancellationToken.None).ConfigureAwait(false),
                    from,
                    to,
                    includeDownloaded: true),
                ReadLibrary(index.GetMovies)));

        var seriesRead = await series.WaitAsync(cancellationToken).ConfigureAwait(false);
        var moviesRead = await movies.WaitAsync(cancellationToken).ConfigureAwait(false);
        return new CalendarResponse(
            (seriesRead.Value ?? []).Select(group => ToDto(group, userId)).ToList(),
            (moviesRead.Value ?? []).Select(movie => ToDto(movie, userId)).ToList(),
            seriesRead.Error,
            moviesRead.Error);
    }

    // Un servizio non configurato non si chiama e non entra in cache.
    private static Task<ArrRead<IReadOnlyList<T>>> ReadAsync<T>(
        ArrEndpoint endpoint, ArrReadCache<IReadOnlyList<T>> cache, string period, Func<Task<IReadOnlyList<T>>> read) =>
        endpoint.IsConfigured
            ? cache.GetAsync($"{endpoint.Url}\n{endpoint.ApiKey}\n{period}", read)
            : Task.FromResult(new ArrRead<IReadOnlyList<T>>([], UpcomingErrors.NotConfigured));

    // Senza la libreria le uscite restano, solo senza il collegamento.
    private IReadOnlyList<T> ReadLibrary<T>(Func<IReadOnlyList<T>> read)
    {
        try
        {
            return read();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Calendario: la libreria non si legge");
            return [];
        }
    }

    private CalendarEpisodeDto ToDto(UpcomingEpisodeGroup group, Guid userId) => new(
        group.SeriesName,
        group.SeasonNumber,
        group.EpisodeNumber,
        group.LastEpisodeNumber,
        group.EpisodeTitle,
        group.AirDateUtc,
        group.TvdbId,
        group.TmdbId,
        group.PosterUrl,
        group.BackdropUrl,
        VisibleId(group.LibrarySeriesIds, userId),
        group.OnServer);

    private CalendarMovieDto ToDto(UpcomingMovie movie, Guid userId) => new(
        movie.Title,
        movie.Year,
        movie.TmdbId,
        movie.DigitalRelease,
        movie.PosterUrl,
        movie.BackdropUrl,
        VisibleId(movie.LibraryItemIds, userId),
        movie.OnServer);

    private string? VisibleId(IReadOnlyList<Guid> ids, Guid userId)
    {
        var id = ids.FirstOrDefault(candidate => CanSee(userId, candidate));
        return id == Guid.Empty ? null : id.ToString("N");
    }

    // Un errore della libreria toglie solo il collegamento, non l'uscita.
    private bool CanSee(Guid userId, Guid itemId)
    {
        try
        {
            return library.CanSee(userId, itemId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Calendario: visibilità non letta");
            return false;
        }
    }
}
