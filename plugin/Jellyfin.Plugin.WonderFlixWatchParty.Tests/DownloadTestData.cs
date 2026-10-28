using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Film, episodi, coda e release finti per i test di DownloadService.</summary>
internal static class DownloadTestData
{
    public const long Gb = 1_000_000_000;

    public static RadarrMovie Movie(int id, bool monitored = true, bool available = true, bool hasFile = false, string title = "Dune", int year = 2021, int runtime = 155) => new()
    {
        Id = id,
        Title = title,
        Year = year,
        Runtime = runtime,
        Monitored = monitored,
        IsAvailable = available,
        HasFile = hasFile,
        QualityProfileId = 4,
        Images = [new ArrImage { CoverType = "fanart", RemoteUrl = "https://img.example/fanart.jpg" }, new ArrImage { CoverType = "Poster", RemoteUrl = "https://img.example/poster.jpg" }],
    };

    public static SonarrEpisode Episode(int id, DateTimeOffset? airDate, bool monitored = true) => new()
    {
        Id = id,
        SeriesId = 7,
        SeasonNumber = 2,
        EpisodeNumber = 5,
        AirDateUtc = airDate,
        Monitored = monitored,
        Series = new SonarrSeries { Title = "Severance", Runtime = 50, QualityProfileId = 6, Images = [new ArrImage { CoverType = "poster", RemoteUrl = "https://img.example/sev.jpg" }] },
    };

    public static ArrQueueItem MovieQueue(int queueId, int movieId, long sizeLeft, string state = "downloading", string status = "downloading") =>
        new() { Id = queueId, MovieId = movieId, Size = 10_000, Sizeleft = sizeLeft, TrackedDownloadState = state, Status = status };

    public static ArrQueueItem EpisodeQueue(int queueId, int episodeId, long sizeLeft) =>
        new() { Id = queueId, EpisodeId = episodeId, SeriesId = 7, SeasonNumber = 2, Size = 10_000, Sizeleft = sizeLeft, TrackedDownloadState = "downloading", Status = "downloading" };

    // Id delle qualità come in Radarr.
    public const int Hdtv720 = 4;
    public const int WebDl1080 = 3;
    public const int WebRip1080 = 15;
    public const int Bluray1080 = 7;

    public static ArrRelease Release(string guid, int qualityId, string quality, double gb, int score, int indexerId = 1) => new()
    {
        Guid = guid,
        IndexerId = indexerId,
        Indexer = "idx" + indexerId,
        Title = "t-" + guid,
        Size = (long)(gb * Gb),
        Seeders = 10,
        Quality = new ArrQualityModel { Quality = new ArrQuality { Id = qualityId, Name = quality, Resolution = quality.EndsWith("720p", StringComparison.Ordinal) ? 720 : 1080 } },
        CustomFormatScore = score,
    };

    // HDTV-720p, poi il gruppo WEB 1080p (WEBDL e WEBRip nella stessa posizione), poi Bluray-1080p.
    public static ArrQualityProfile MainProfile(int id) => new()
    {
        Id = id,
        Name = "Main",
        Items =
        [
            new ArrQualityProfileItem { Allowed = true, Quality = new ArrQuality { Id = Hdtv720, Name = "HDTV-720p" } },
            new ArrQualityProfileItem
            {
                Allowed = true,
                Name = "WEB 1080p",
                Items =
                [
                    new ArrQualityProfileItem { Allowed = true, Quality = new ArrQuality { Id = WebDl1080, Name = "WEBDL-1080p" } },
                    new ArrQualityProfileItem { Allowed = true, Quality = new ArrQuality { Id = WebRip1080, Name = "WEBRip-1080p" } },
                ],
            },
            new ArrQualityProfileItem { Allowed = true, Quality = new ArrQuality { Id = Bluray1080, Name = "Bluray-1080p" } },
        ],
    };
}
