using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Dal risultato di Prowlarr e dal <c>/parse</c> di Sonarr/Radarr alla stessa <see cref="ArrRelease"/> che le regole già usano.</summary>
public static class ParsedRelease
{
    /// <summary>
    /// La release di Prowlarr come la leggono le regole; <c>IndexerId</c> è quello del servizio. Se il parse la attribuisce
    /// ad altro (serie o film diversi, altra stagione, episodio non coperto) <c>WrongTitle</c> non è null.
    /// </summary>
    public static ArrRelease From(ProwlarrRelease found, ArrParse parse, int serviceIndexerId, DownloadKey key)
    {
        var info = key.Kind == DownloadKinds.Movie ? parse.ParsedMovieInfo : parse.ParsedEpisodeInfo;
        var release = new ArrRelease
        {
            Guid = found.Guid,
            IndexerId = serviceIndexerId,
            Indexer = found.Indexer,
            Title = found.Title,
            Size = found.Size,
            Seeders = found.Seeders,
            Quality = info?.Quality,
            CustomFormatScore = parse.CustomFormatScore,
            Rejections = [],
            Source = ReleaseSource.Prowlarr,
            DownloadUrl = found.DownloadUrl,
            MagnetUrl = found.MagnetUrl,
            Protocol = found.Protocol,
            PublishDate = found.PublishDate,
        };

        if (key.Kind == DownloadKinds.Movie)
        {
            release.WrongTitle = parse.Movie is { } movie && movie.Id == key.Id ? null : "altro film";
            return release;
        }

        var episodes = parse.Episodes?.OfType<SonarrEpisode>().ToList() ?? [];
        var season = key.Season;
        var seriesId = key.Id;
        if (key.Kind == DownloadKinds.Episode)
        {
            // Nella chiave di un episodio ci sono solo l'id dell'episodio: serie e stagione vengono da lui.
            if (episodes.FirstOrDefault(e => e.Id == key.Id) is not { } wanted)
            {
                release.WrongTitle = "episodio non coperto";
                return release;
            }

            season = wanted.SeasonNumber;
            seriesId = wanted.SeriesId;
        }

        var numbers = episodes.Where(e => e.SeasonNumber == season).Select(e => e.EpisodeNumber).ToList();
        release.WrongTitle =
            parse.Series is not { } series || series.Id != seriesId ? "altra serie"
            : numbers.Count == 0 ? "altra stagione"
            : null;
        release.FullSeason = info?.FullSeason ?? false;
        release.SeasonNumber = season;
        release.EpisodeNumbers = numbers;
        release.MappedEpisodeNumbers = [.. numbers];
        return release;
    }
}
