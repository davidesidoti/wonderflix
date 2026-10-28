using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadServiceSearchTests : IDisposable
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
    private List<ArrRelease?> _releases = [];

    public DownloadServiceSearchTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : []);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }, new ArrIndexer { Id = 3, Priority = 10 }]);
        _service = new DownloadService(
            _arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        _service.Load();
    }

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    private Task<CycleReport> Cycle() => _service.RunCycleAsync(CancellationToken.None);

    // Un film scaricato da WonderFlix con la release data, poi importato da Radarr.
    private async Task GrabAndImport(ArrRelease release)
    {
        _movies = [Movie(12)];
        _releases = [release];
        await Cycle();
        _releases = [];

        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        await Cycle();

        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        _movies = [Movie(12, hasFile: true)];
        await Cycle();
    }

    [Fact]
    public async Task TheRuleChoiceIsGrabbed()
    {
        _movies = [Movie(12, title: "Animals", year: 2025, runtime: 106)];
        _releases =
        [
            Release("a", WebDl1080, "WEBDL-1080p", 2.9, 150),
            Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3),
            Release("c", WebRip1080, "WEBRip-1080p", 4.83, 150),
        ];

        var report = await Cycle();

        Assert.Equal((1, 1), (report.Searched, report.Grabbed));
        Assert.Equal((ArrKind.Radarr, "movieId=12"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.Equal((ArrKind.Radarr, "b", 3), Assert.Single(_arr.GrabCalls));
        Assert.Equal([ArrKind.Radarr], _arr.QualityProfileCalls);
        Assert.Equal([ArrKind.Radarr], _arr.IndexerCalls);

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (string?)null), (entry.State, entry.Reason));
        Assert.Equal(((int?)150, (int?)WebRip1080, "Main"), (entry.CurrentScore, entry.CurrentQualityId, entry.ProfileName));

        var choice = Assert.Single(Store().Load().Choices);
        Assert.Equal(("movie:12", DownloadKinds.Movie, "Animals (2025)", "https://img.example/poster.jpg", T0), (choice.Key, choice.Kind, choice.Title, choice.PosterUrl, choice.At));
        Assert.Equal(("b", 3, "idx3", "t-b"), (choice.Guid, choice.IndexerId, choice.Indexer, choice.ReleaseTitle));
        Assert.Equal(("WEBRip-1080p", WebRip1080, 1080, (long)(1.89 * Gb), 150, (int?)10), (choice.Quality, choice.QualityId, choice.Resolution, choice.SizeBytes, choice.Score, choice.Seeders));
        Assert.Equal(((long?)null, (int?)null, false), (choice.PreviousSizeBytes, choice.PreviousScore, choice.ByAdmin));

        // Un giro subito dopo (un nudge): Radarr non l'ha ancora in coda, ma non si scarica di nuovo.
        _time.Advance(DownloadService.NudgeDelay);
        await Cycle();
        Assert.Single(_arr.GrabCalls);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task ACycleSearchesAtMostTenTitles()
    {
        _movies = [.. Enumerable.Range(1, 25).Select(id => (RadarrMovie?)Movie(id))];

        var report = await Cycle();
        Assert.Equal(DownloadService.MaxSearchesPerCycle, report.Searched);
        var first = _arr.SearchReleaseCalls.Select(c => c.Query).ToList();

        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        var second = _arr.SearchReleaseCalls.Skip(first.Count).Select(c => c.Query).ToList();

        Assert.Equal(10, first.Distinct().Count());
        Assert.Equal(10, second.Distinct().Count());
        Assert.Empty(first.Intersect(second));
        Assert.Equal(2, _arr.QualityProfileCalls.Count);
    }

    [Fact]
    public async Task ATitleInTheQueueIsNotSearched()
    {
        _movies = [Movie(12), Movie(13)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];

        await Cycle();

        Assert.Equal((ArrKind.Radarr, "movieId=13"), Assert.Single(_arr.SearchReleaseCalls));
    }

    [Fact]
    public async Task NothingValidWaitsSixHours()
    {
        _movies = [Movie(12)];
        _releases = [Release("small", WebRip1080, "WEBRip-1080p", 0.5, 150)];

        await Cycle();

        Assert.Empty(_arr.GrabCalls);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (string?)null), (entry.State, entry.Reason));
        Assert.Equal(((DateTimeOffset?)T0, (DateTimeOffset?)(T0 + TimeSpan.FromHours(6))), (entry.LastSearchAt, entry.NextSearchAt));

        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Single(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task AfterAWeekNothingNeedsYou()
    {
        _missing = [Episode(34, T0 - TimeSpan.FromDays(8))];

        await Cycle();

        Assert.Equal((ArrKind.Sonarr, "episodeId=34"), Assert.Single(_arr.SearchReleaseCalls));
        var entry = Saved("episode:34")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.NothingFound), (entry.State, entry.Reason));
        Assert.Equal(T0 + TimeSpan.FromHours(24), entry.NextSearchAt);

        _time.Advance(TimeSpan.FromHours(24));
        await Cycle();
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
    }

    [Fact]
    public async Task BelowMinScoreNeedsYouAtOnce()
    {
        _movies = [Movie(12)];
        _releases = [Release("eng", WebRip1080, "WEBRip-1080p", 4, 10)];

        await Cycle();

        Assert.Empty(_arr.GrabCalls);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.BelowMinScore), (entry.State, entry.Reason));
        Assert.Equal(T0 + TimeSpan.FromHours(6), entry.NextSearchAt);

        // Si cerca ancora: una release valida più tardi si scarica.
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)];
        await Cycle();
        Assert.Equal("ita", Assert.Single(_arr.GrabCalls).Guid);
        entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (string?)null), (entry.State, entry.Reason));
    }

    [Fact]
    public async Task AnImportBelowTargetWatchesForUpgrades()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)null), (entry.State, entry.QueueId));
        Assert.Equal(T0 + TimeSpan.FromDays(30), entry.UpgradeUntil);
        Assert.Equal(_time.GetUtcNow() + TimeSpan.FromHours(6), entry.NextSearchAt);
    }

    [Fact]
    public async Task AnImportAtTargetLeaves()
    {
        _movies = [Movie(12)];
        _releases = [Release("ita-eng", WebRip1080, "WEBRip-1080p", 4, 150)];
        await Cycle();

        // Importato prima che il giro lo veda in coda.
        _time.Advance(DownloadService.CycleInterval);
        _movies = [Movie(12, hasFile: true)];
        await Cycle();

        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task AnImportOfSomeoneElsesDownloadLeaves()
    {
        _movies = [Movie(12)];
        _radarrQueue = [MovieQueue(90, 12, 5_000)];
        await Cycle();

        _radarrQueue = [];
        _movies = [Movie(12, hasFile: true)];
        await Cycle();

        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task AnUpgradeNeedsAHigherScoreAndAnImport()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));

        // Stesso punteggio, più leggera: no.
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("lighter", WebRip1080, "WEBRip-1080p", 2.5, 50)];
        await Cycle();

        // Qualità più alta nel profilo ma stesso punteggio: Radarr la importerebbe, ma non è un upgrade.
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("bluray", Bluray1080, "Bluray-1080p", 8, 50)];
        await Cycle();

        // Punteggio più alto ma qualità più bassa nel profilo: Radarr non la importerebbe.
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("720", Hdtv720, "HDTV-720p", 3, 150)];
        await Cycle();

        Assert.Single(_arr.GrabCalls);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (string?)null), (entry.State, entry.Reason));
        Assert.Equal(_time.GetUtcNow() + TimeSpan.FromHours(6), entry.NextSearchAt);

        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150)];
        var report = await Cycle();

        Assert.Equal(1, report.Grabbed);
        Assert.Equal("ita-eng", _arr.GrabCalls[^1].Guid);
        var choice = Store().Load().Choices[0];
        Assert.Equal(("ita-eng", (int?)50, (long?)(4 * Gb)), (choice.Guid, choice.PreviousScore, choice.PreviousSizeBytes));
        entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (int?)150), (entry.State, entry.CurrentScore));
    }

    [Fact]
    public async Task TheUpgradeWindowCloses()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));

        // Anche un episodio: Sonarr lo toglie dai mancanti quando ha il file.
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        _releases = [Release("ep", WebRip1080, "WEBRip-1080p", 1, 50)];
        await Cycle();
        _releases = [];
        _missing = [];
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("episode:34")!.State);
        var episodeUntil = Saved("episode:34")!.UpgradeUntil!.Value;

        _time.SetUtcNow(T0 + DownloadSchedule.UpgradeWindow - TimeSpan.FromMinutes(1));
        await Cycle();
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("movie:12")!.State);

        _time.SetUtcNow(T0 + DownloadSchedule.UpgradeWindow);
        await Cycle();
        Assert.Null(Saved("movie:12"));
        Assert.NotNull(Saved("episode:34"));

        _time.SetUtcNow(episodeUntil);
        await Cycle();
        Assert.Null(Saved("episode:34"));
    }

    [Fact]
    public async Task AnUnmonitoredMovieLeavesTheUpgradeWatch()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));

        _movies = [Movie(12, monitored: false, hasFile: true)];
        await Cycle();

        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task TurningOffMidCycleStops()
    {
        _movies = [Movie(12), Movie(13), Movie(14)];
        _arr.Releases = (_, _) =>
        {
            _settings.Enabled = false;
            return Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        };

        var report = await Cycle();

        Assert.Equal(1, report.Searched);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Equal(3, Store().Load().Entries.Count);
    }

    [Fact]
    public async Task ASearchErrorKeepsTheEntry()
    {
        _movies = [Movie(12)];
        _arr.Releases = (_, _) => Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable));

        var report = await Cycle();

        Assert.Equal((1, 0, (string?)null), (report.Searched, report.Grabbed, report.RadarrError));
        Assert.Empty(_arr.GrabCalls);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, DownloadReasons.SearchFailed, (DateTimeOffset?)T0), (entry.State, entry.Reason, entry.NextSearchAt));

        // Si riprova al giro dopo.
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
    }

    [Fact]
    public async Task AGrabErrorKeepsTheEntryWaiting()
    {
        _movies = [Movie(12)];
        _releases = [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)];
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable));

        var report = await Cycle();

        Assert.Equal((1, 0), (report.Searched, report.Grabbed));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, DownloadReasons.SearchFailed, (int?)null), (entry.State, entry.Reason, entry.CurrentScore));
        Assert.Equal(T0 + TimeSpan.FromHours(6), entry.NextSearchAt);
        Assert.Empty(Store().Load().Choices);
    }

    [Fact]
    public async Task AProfileReadErrorSkipsThatService()
    {
        _movies = [Movie(12)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        _arr.QualityProfiles = kind => kind == ArrKind.Radarr
            ? Task.FromException<IReadOnlyList<ArrQualityProfile?>>(new ArrException(ArrError.Unauthorized))
            : Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(6)]);

        var report = await Cycle();

        Assert.Equal(("Unauthorized", (string?)null), (report.RadarrError, report.SonarrError));
        Assert.Equal(("Unauthorized", (string?)null), (_service.LastErrors.Radarr, _service.LastErrors.Sonarr));
        Assert.Equal((ArrKind.Sonarr, "episodeId=34"), Assert.Single(_arr.SearchReleaseCalls));
        var movie = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (string?)null, (DateTimeOffset?)T0), (movie.State, movie.Reason, movie.NextSearchAt));
    }
}
