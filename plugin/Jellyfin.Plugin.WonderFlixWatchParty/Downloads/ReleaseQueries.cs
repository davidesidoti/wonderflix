using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Le query per titolo da mandare a Prowlarr per una stagione, un episodio o un film (spec §3). Mai per ID.</summary>
public static class ReleaseQueries
{
    /// <summary>Al massimo così tante query Prowlarr per ricerca.</summary>
    public const int MaxQueries = 8;

    /// <summary>Stagione: il titolo con la stagione, poi i titoli alternativi di quella stagione, poi quelli generali.</summary>
    public static IReadOnlyList<(string Type, string Query, int? Season, int? Episode)> ForSeason(SonarrSeries series, int season)
    {
        var all = new List<(string Type, string Query, int? Season, int? Episode)> { ("tvsearch", series.Title ?? string.Empty, season, null) };
        var alts = Alternates(series);
        all.AddRange(alts.Where(a => a.SceneSeasonNumber == season).Select(Search));
        all.AddRange(alts.Where(a => a.SceneSeasonNumber == -1 || a.SeasonNumber == -1).Select(Search));
        return Finish(all);
    }

    /// <summary>Episodio: tvsearch; per gli anime anche il titolo con il numero assoluto, e i titoli della stagione scene con il numero scene.</summary>
    public static IReadOnlyList<(string Type, string Query, int? Season, int? Episode)> ForEpisode(SonarrSeries series, SonarrEpisode episode)
    {
        var title = series.Title ?? string.Empty;
        var all = new List<(string Type, string Query, int? Season, int? Episode)> { ("tvsearch", title, episode.SeasonNumber, episode.EpisodeNumber) };
        if (series.SeriesType == "anime")
        {
            if (episode.AbsoluteEpisodeNumber is { } abs)
            {
                all.Add(("search", $"{title} {abs:00}", null, null));
            }

            if (episode.SceneSeasonNumber is { } sceneSeason && episode.SceneEpisodeNumber is { } sceneEpisode)
            {
                all.AddRange(Alternates(series)
                    .Where(a => a.SceneSeasonNumber == sceneSeason)
                    .Select(a => ("search", $"{a.Title} {sceneEpisode:00}", (int?)null, (int?)null)));
            }
        }

        return Finish(all);
    }

    /// <summary>Film: titolo e anno, il titolo originale, poi i titoli alternativi in italiano e in inglese.</summary>
    public static IReadOnlyList<(string Type, string Query, int? Season, int? Episode)> ForMovie(RadarrMovie movie)
    {
        var all = new List<(string Type, string Query, int? Season, int? Episode)>
        {
            ("movie", $"{movie.Title} {movie.Year}", null, null),
            ("movie", movie.OriginalTitle ?? string.Empty, null, null),
        };
        var alts = (movie.AlternateTitles ?? []).OfType<RadarrAlternateTitle>().ToList();
        foreach (var language in new[] { "Italian", "English" })
        {
            all.AddRange(alts.Where(a => a.Language?.Name == language).Select(a => ("movie", a.Title ?? string.Empty, (int?)null, (int?)null)));
        }

        return Finish(all);
    }

    private static List<SonarrAlternateTitle> Alternates(SonarrSeries series) => (series.AlternateTitles ?? []).OfType<SonarrAlternateTitle>().ToList();

    private static (string Type, string Query, int? Season, int? Episode) Search(SonarrAlternateTitle alt) => ("search", alt.Title ?? string.Empty, null, null);

    // Toglie le query vuote e i doppioni (senza maiuscole e spazi doppi), tiene l'ordine e tronca a MaxQueries.
    private static List<(string Type, string Query, int? Season, int? Episode)> Finish(List<(string Type, string Query, int? Season, int? Episode)> all)
    {
        var seen = new HashSet<(string, string, int?, int?)>();
        var result = new List<(string Type, string Query, int? Season, int? Episode)>();
        foreach (var (type, query, season, episode) in all)
        {
            var clean = Regex.Replace(query, @"\s+", " ").Trim();
            if (clean.Length > 0 && seen.Add((type, clean.ToLowerInvariant(), season, episode)))
            {
                result.Add((type, clean, season, episode));
            }
        }

        return result.Take(MaxQueries).ToList();
    }
}
