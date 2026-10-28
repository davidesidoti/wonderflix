using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadServiceCycleTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    private List<RadarrMovie?> _movies = [];
    private List<SonarrEpisode?> _missing = [];
    private List<ArrQueueItem?> _radarrQueue = [];
    private List<ArrQueueItem?> _sonarrQueue = [];

    public DownloadServiceCycleTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : _sonarrQueue);
        _service = new DownloadService(
            _arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        _service.Load();
    }

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    // Lo stato salvato a fine giro: i test guardano downloads.json.
    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    private static RadarrMovie Movie(int id, bool monitored = true, bool available = true, bool hasFile = false) => new()
    {
        Id = id,
        Title = "Dune",
        Year = 2021,
        Runtime = 155,
        Monitored = monitored,
        IsAvailable = available,
        HasFile = hasFile,
        QualityProfileId = 4,
        Images = [new ArrImage { CoverType = "fanart", RemoteUrl = "https://img.example/fanart.jpg" }, new ArrImage { CoverType = "Poster", RemoteUrl = "https://img.example/poster.jpg" }],
    };

    private static SonarrEpisode Episode(int id, DateTimeOffset? airDate, bool monitored = true) => new()
    {
        Id = id,
        SeriesId = 7,
        SeasonNumber = 2,
        EpisodeNumber = 5,
        AirDateUtc = airDate,
        Monitored = monitored,
        Series = new SonarrSeries { Title = "Severance", Runtime = 50, QualityProfileId = 6, Images = [new ArrImage { CoverType = "poster", RemoteUrl = "https://img.example/sev.jpg" }] },
    };

    private static ArrQueueItem MovieQueue(int queueId, int movieId, long sizeLeft, string state = "downloading") =>
        new() { Id = queueId, MovieId = movieId, Size = 10_000, Sizeleft = sizeLeft, TrackedDownloadState = state };

    private static ArrQueueItem EpisodeQueue(int queueId, int episodeId, long sizeLeft) =>
        new() { Id = queueId, EpisodeId = episodeId, SeriesId = 7, SeasonNumber = 2, Size = 10_000, Sizeleft = sizeLeft, TrackedDownloadState = "downloading" };

    [Fact]
    public async Task ADisabledServiceDoesNothing()
    {
        _settings.Enabled = false;

        Assert.Same(CycleReport.Skipped, await _service.RunCycleAsync(CancellationToken.None));

        Assert.Equal(0, _arr.LibraryMovieCalls);
        Assert.Equal(0, _arr.MissingEpisodeCalls);
        Assert.Empty(_arr.QueueCalls);
    }

    [Fact]
    public async Task AMissingAvailableMovieGetsAnEntry()
    {
        _movies = [Movie(12), null];

        var report = await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal(new CycleReport(0, 0, null, null), report);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadKinds.Movie, "Dune (2021)", "https://img.example/poster.jpg"), (entry.Kind, entry.Title, entry.PosterUrl));
        Assert.Equal((DownloadStates.Waiting, (string?)null, T0, (DateTimeOffset?)T0), (entry.State, entry.Reason, entry.AvailableSince, entry.NextSearchAt));
        Assert.Equal((4, 155), (entry.ProfileId, entry.RuntimeMinutes));

        // Il giro dopo non la ricrea: la data è quella della prima volta.
        _time.Advance(TimeSpan.FromHours(1));
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(T0, Saved("movie:12")!.AvailableSince);
    }

    [Fact]
    public async Task AMovieNotYetAvailableHasNone()
    {
        _movies = [Movie(12, available: false)];

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task AnUnmonitoredMovieHasNone()
    {
        _movies = [Movie(12, monitored: false), Movie(13, hasFile: true)];

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task AnAiredMissingEpisodeGetsAnEntry()
    {
        var aired = T0 - TimeSpan.FromDays(3);
        _missing = [Episode(34, aired)];

        await _service.RunCycleAsync(CancellationToken.None);

        var entry = Saved("episode:34")!;
        Assert.Equal((DownloadKinds.Episode, "Severance · S02E05", "https://img.example/sev.jpg"), (entry.Kind, entry.Title, entry.PosterUrl));
        Assert.Equal((DownloadStates.Waiting, aired, (DateTimeOffset?)T0), (entry.State, entry.AvailableSince, entry.NextSearchAt));
        Assert.Equal((6, 50), (entry.ProfileId, entry.RuntimeMinutes));
    }

    [Fact]
    public async Task AFutureEpisodeHasNone()
    {
        _missing = [Episode(34, T0 + TimeSpan.FromDays(1)), Episode(35, null), Episode(36, T0 - TimeSpan.FromDays(1), monitored: false)];

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task AQueuedTitleIsDownloading()
    {
        // Nessuna voce prima: il download l'ha avviato qualcun altro.
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        _sonarrQueue = [EpisodeQueue(91, 34, 7_000)];

        await _service.RunCycleAsync(CancellationToken.None);

        var movie = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (int?)90, (long?)5_000, (DateTimeOffset?)T0), (movie.State, movie.QueueId, movie.LastSizeLeft, movie.LastProgressAt));
        var episode = Saved("episode:34")!;
        Assert.Equal((DownloadStates.Downloading, (int?)91), (episode.State, episode.QueueId));
    }

    [Fact]
    public async Task ASlowDownloadIsNotStalled()
    {
        _movies = [Movie(12)];
        var sizeLeft = 10_000L;
        for (var cycle = 0; cycle < 3 * 24 * 4; cycle++)
        {
            // Un byte ogni 6 ore: lento ma vivo.
            if (cycle % 24 == 0)
            {
                sizeLeft--;
            }

            _radarrQueue = [MovieQueue(90, 12, sizeLeft)];
            await _service.RunCycleAsync(CancellationToken.None);
            _time.Advance(DownloadService.CycleInterval);
        }

        Assert.Empty(_arr.RemoveFromQueueCalls);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task AStuckDownloadIsRemovedAfterADay()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        await _service.RunCycleAsync(CancellationToken.None);

        _time.Advance(DownloadSchedule.StalledAfter - TimeSpan.FromMinutes(1));
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Empty(_arr.RemoveFromQueueCalls);

        _time.Advance(TimeSpan.FromMinutes(1));
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal((ArrKind.Radarr, 90, true), Assert.Single(_arr.RemoveFromQueueCalls));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (int?)null, (DateTimeOffset?)_time.GetUtcNow()), (entry.State, entry.QueueId, entry.NextSearchAt));
    }

    [Fact]
    public async Task AStuckDownloadThatCannotBeRemovedStays()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        _arr.RemoveFromQueue = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable));
        await _service.RunCycleAsync(CancellationToken.None);

        _time.Advance(DownloadSchedule.StalledAfter);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Single(_arr.RemoveFromQueueCalls);
        Assert.Equal((DownloadStates.Downloading, (int?)90), (Saved("movie:12")!.State, Saved("movie:12")!.QueueId));
    }

    [Fact]
    public async Task AFailedDownloadGoesBackToWaiting()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        await _service.RunCycleAsync(CancellationToken.None);

        _radarrQueue = [];
        _time.Advance(TimeSpan.FromHours(2));
        await _service.RunCycleAsync(CancellationToken.None);

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (int?)null, (long?)null, (DateTimeOffset?)_time.GetUtcNow()), (entry.State, entry.QueueId, entry.LastSizeLeft, entry.NextSearchAt));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task AnImportedDownloadLeaves()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        _sonarrQueue = [EpisodeQueue(91, 34, 7_000)];
        await _service.RunCycleAsync(CancellationToken.None);

        // Radarr ha il file; Sonarr ha tolto l'episodio dai mancanti.
        _movies = [Movie(12, hasFile: true)];
        _radarrQueue = [];
        _missing = [];
        _sonarrQueue = [];
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task ImportBlockedNeedsYou()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 0, state: "importBlocked")];

        await _service.RunCycleAsync(CancellationToken.None);

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.ImportBlocked, (int?)90), (entry.State, entry.Reason, entry.QueueId));

        // Fermo in attesa dell'admin non vuol dire download fermo.
        _time.Advance(TimeSpan.FromDays(2));
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task ATitleDownloadedElsewhereLeaves()
    {
        _movies = [Movie(12), Movie(13), Movie(14)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(4, Store().Load().Entries.Count);

        // 12 ha il file, 13 non è più monitorato, 14 non c'è più; l'episodio non manca più.
        _movies = [Movie(12, hasFile: true), Movie(13, monitored: false)];
        _missing = [];
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task OneServiceDownKeepsTheOther()
    {
        _movies = [Movie(12)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        await _service.RunCycleAsync(CancellationToken.None);

        _arr.MissingEpisodes = () => Task.FromException<IReadOnlyList<SonarrEpisode?>>(new ArrException(ArrError.Unreachable));
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        var report = await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal(("Unreachable", (string?)null), (report.SonarrError, report.RadarrError));
        Assert.Equal(("Unreachable", (string?)null), _service.LastErrors);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
        Assert.Equal(DownloadStates.Waiting, Saved("episode:34")!.State);
    }

    [Fact]
    public async Task AServiceNotConfiguredIsSkipped()
    {
        _arrSettings.Radarr = ArrEndpoint.None;
        _arr.MissingEpisodes = () => Task.FromException<IReadOnlyList<SonarrEpisode?>>(new InvalidOperationException("boom"));

        var report = await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal(("Unreachable", "NotConfigured"), (report.SonarrError, report.RadarrError));
        Assert.Equal(0, _arr.LibraryMovieCalls);
        Assert.DoesNotContain(ArrKind.Radarr, _arr.QueueCalls);
    }

    [Fact]
    public void NudgeRaisesNudged()
    {
        var raised = 0;
        _service.Nudged += () => raised++;

        _service.Nudge();

        Assert.Equal(1, raised);
    }
}
