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
    private DownloadService _service;

    private List<RadarrMovie?> _movies = [];
    private List<SonarrEpisode?> _missing = [];
    private List<ArrQueueItem?> _radarrQueue = [];
    private List<ArrRelease?> _releases = [];
    private int _fileScore = 50;

    public DownloadServiceSearchTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : []);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.MovieFiles = ids => Task.FromResult<IReadOnlyList<ArrFile?>>([File(ids[0], WebRip1080, _fileScore)]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }, new ArrIndexer { Id = 3, Priority = 10 }]);
        _service = NewService();
    }

    private DownloadService NewService()
    {
        var service = new DownloadService(
            _arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        service.Load();
        return service;
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

    // Dopo GrabAndImport (50): un upgrade scaricato e visto in coda; il test decide come finisce.
    private async Task StartUpgrade(ArrRelease release)
    {
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [release];
        await Cycle();
        _releases = [];

        // Un nudge subito dopo: non ancora in coda e il file è quello vecchio, ma non è un upgrade fallito.
        _time.Advance(DownloadService.NudgeDelay);
        await Cycle();
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
        Assert.Empty(_arr.MovieFileCalls);

        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [MovieQueue(91, 12, 5_000)];
        await Cycle();
        Assert.Equal((DownloadStates.Downloading, (int?)50), (Saved("movie:12")!.State, Saved("movie:12")!.PreviousScore));
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

    // Un film 12 già in elenco, cambiato dal test sul disco e riletto dal servizio.
    private async Task Seed(Action<DownloadEntry> change)
    {
        _movies = [Movie(12)];
        await Cycle();
        var book = Store().Load();
        var entry = book.Get("movie:12")!;
        entry.NextSearchAt = T0;
        change(entry);
        Store().Save(book);
        _service = NewService();
    }

    // Un titolo silenziato: Waiting/NothingFound, disponibile da 10 giorni, ricerca scaduta.
    private Task SeedSnoozed() => Seed(e =>
    {
        e.State = DownloadStates.Waiting;
        e.Reason = DownloadReasons.NothingFound;
        e.Snoozed = true;
        e.AvailableSince = T0 - TimeSpan.FromDays(10);
        e.NextSearchAt = T0;
    });

    // Il film 12 col file, tappabuchi in UpgradeWatch (minimo 100, obiettivo 150), ricerca scaduta.
    private async Task SeedStopgap(string kind, int score, double gb)
    {
        _settings.Thresholds[(ArrKind.Radarr, 4)] = new ProfileThresholds(100, 150);
        await Seed(e =>
        {
            e.State = DownloadStates.UpgradeWatch;
            e.Stopgap = kind;
            e.CurrentScore = score;
            e.CurrentQualityId = WebRip1080;
            e.CurrentSizeBytes = (long)(gb * Gb);
            e.UpgradeUntil = T0 + DownloadSchedule.UpgradeWindow;
        });
        _movies = [Movie(12, hasFile: true)];
    }

    [Fact]
    public async Task AScoreStopgapStepsUpBelowTheMinimum()
    {
        await SeedStopgap(DownloadStopgaps.Score, 40, 4);
        _releases = [Release("70", WebRip1080, "WEBRip-1080p", 4, 70)];
        await Cycle();
        _releases = [];
        Assert.Equal("70", _arr.GrabCalls[^1].Guid);
        Assert.False(Saved("movie:12")!.ManualImportPending);

        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [MovieQueue(91, 12, 5_000)];
        await Cycle();

        // Importato: ancora sotto il minimo, resta tappabuchi.
        _arr.MovieFiles = ids => Task.FromResult<IReadOnlyList<ArrFile?>>([new ArrFile { Id = ids[0], CustomFormatScore = 70, Size = 4 * Gb, Quality = new ArrQualityModel { Quality = new ArrQuality { Id = WebRip1080 } } }]);
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)70, DownloadStopgaps.Score), (entry.State, entry.CurrentScore, entry.Stopgap));
    }

    [Fact]
    public async Task AScoreStopgapIgnoresAnEqualScore()
    {
        await SeedStopgap(DownloadStopgaps.Score, 40, 4);
        _releases = [Release("40", WebRip1080, "WEBRip-1080p", 5, 40)];

        await Cycle();

        Assert.Empty(_arr.GrabCalls);
    }

    [Fact]
    public async Task ASizeStopgapTakesAnEqualScoreAndForcesTheImport()
    {
        // Stessa qualità e stesso punteggio: Radarr non la importerebbe, si importa a mano. Sotto l'obiettivo, così la voce resta.
        await SeedStopgap(DownloadStopgaps.Size, 120, 1);
        _releases = [Release("heavy", WebRip1080, "WEBRip-1080p", 4, 120)];

        await Cycle();

        Assert.Equal("heavy", Assert.Single(_arr.GrabCalls).Guid);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, true), (entry.State, entry.ManualImportPending));

        // Radarr la blocca ("Not an upgrade"): il giro la importa a mano.
        var blocked = MovieQueue(91, 12, 0, state: "importBlocked", status: "completed");
        blocked.DownloadId = "D1";
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [new ArrManualImportItem { Path = "/dl/heavy.mkv", DownloadId = "D1", Movie = new ArrFileRef { Id = 12 }, Quality = System.Text.Json.JsonDocument.Parse("""{"quality":{"id":15}}""").RootElement, Rejections = [] }]);
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [blocked];
        await Cycle();
        Assert.Single(_arr.ManualImportCalls);

        // Il file nuovo: stessa qualità e punteggio, ma pesante. È l'import riuscito, non un upgrade fallito.
        _arr.MovieFiles = ids => Task.FromResult<IReadOnlyList<ArrFile?>>([new ArrFile { Id = ids[0], CustomFormatScore = 120, Size = 4 * Gb, Quality = new ArrQualityModel { Quality = new ArrQuality { Id = WebRip1080 } } }]);
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();

        entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (string?)null, (long?)(4 * Gb)), (entry.State, entry.Stopgap, entry.CurrentSizeBytes));

        // Alla ricerca dopo la stessa release non è un upgrade.
        _time.Advance(TimeSpan.FromDays(1));
        await Cycle();
        Assert.Single(_arr.GrabCalls);
    }

    [Fact]
    public async Task ASizeStopgapNeverTakesATooSmallRelease()
    {
        await SeedStopgap(DownloadStopgaps.Size, 150, 1);
        _releases = [Release("small", WebRip1080, "WEBRip-1080p", 1, 200)];

        await Cycle();

        Assert.Empty(_arr.GrabCalls);
    }

    [Fact]
    public async Task NothingChosenKeepsASummary()
    {
        _movies = [Movie(12)];
        _releases = [Release("low", WebRip1080, "WEBRip-1080p", 4, 40), Release("small", WebRip1080, "WEBRip-1080p", 0.5, 150)];

        await Cycle();

        var summary = Saved("movie:12")!.Summary!;
        Assert.Equal((2, (int?)40, 1, true), (summary.Found, summary.BestScore, summary.TooSmall, summary.StopgapAvailable));
    }

    [Fact]
    public async Task ASnoozedTitleStaysQuietWhenNothingIsFound()
    {
        await SeedSnoozed();

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, DownloadReasons.NothingFound, true), (entry.State, entry.Reason, entry.Snoozed));
        Assert.Equal(T0 + DownloadSchedule.SnoozedPace, entry.NextSearchAt);
    }

    [Fact]
    public async Task ASnoozedTitleSpeaksAgainWhenSomethingLowIsFound()
    {
        await SeedSnoozed();
        _releases = [Release("low", WebRip1080, "WEBRip-1080p", 4, 40)];

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.BelowMinScore, false), (entry.State, entry.Reason, entry.Snoozed));
    }

    [Fact]
    public async Task AGrabClearsSnoozeAndSummary()
    {
        await SeedSnoozed();
        _releases = [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)];

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, false, (DownloadSummary?)null), (entry.State, entry.Snoozed, entry.Summary));
    }

    [Fact]
    public async Task ARefusedReleaseIsRememberedAndSkipped()
    {
        _movies = [Movie(12)];
        _releases = [Release("a", WebRip1080, "WEBRip-1080p", 4, 150)];
        _arr.Grab = (_, guid, _) => guid == "a" ? Task.FromException(new ArrException(ArrError.Unreachable, status: 500)) : Task.CompletedTask;

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal([DownloadRule.ReleaseId("a", 1)], entry.RefusedReleases);
        Assert.Equal(T0 + DownloadService.CycleInterval, entry.NextSearchAt);

        _time.Advance(DownloadService.CycleInterval);
        _releases = [Release("a", WebRip1080, "WEBRip-1080p", 4, 150), Release("b", WebRip1080, "WEBRip-1080p", 4, 100)];
        await Cycle();

        Assert.Equal("b", _arr.GrabCalls.Last().Guid);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task AtMostTwentyRefusedReleases()
    {
        await Seed(e => e.RefusedReleases = [.. Enumerable.Range(0, 20).Select(i => DownloadRule.ReleaseId($"x{i}", 1))]);
        _releases = [Release("a", WebRip1080, "WEBRip-1080p", 4, 150)];
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        await Cycle();

        var refused = Saved("movie:12")!.RefusedReleases!;
        Assert.Equal(20, refused.Count);
        Assert.DoesNotContain(DownloadRule.ReleaseId("x0", 1), refused);
        Assert.Equal(DownloadRule.ReleaseId("a", 1), refused[^1]);
    }

    [Fact]
    public async Task AnImportBelowTargetWatchesForUpgrades()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)null), (entry.State, entry.QueueId));
        Assert.Equal(T0 + TimeSpan.FromDays(30), entry.UpgradeUntil);

        // Un primo download non rilegge il file (decisione 2).
        Assert.Empty(_arr.MovieFileCalls);
        Assert.Equal(_time.GetUtcNow() + TimeSpan.FromHours(6), entry.NextSearchAt);
    }

    [Fact]
    public async Task AnAcceptedImportDoesNotWatchUpgrades()
    {
        // "Alleggerisci" (spec U): una release più leggera scelta dall'admin; il file importato sotto l'obiettivo non resta in UpgradeWatch.
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        _releases = [Release("light", WebRip1080, "WEBRip-1080p", 2, 50)];
        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("movie:12", "light", 1, CancellationToken.None, lighten: true));

        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [MovieQueue(91, 12, 2_000)];
        await Cycle();
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);

        // Il file è cambiato ma sotto l'obiettivo.
        _fileScore = 60;
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();

        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task AnAcceptedUpgradeWatchIsNotSearched()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("movie:12")!.State);
        Assert.True(_service.Accept("movie:12"));

        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150)];
        await Cycle();

        Assert.Single(_arr.GrabCalls);
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("movie:12")!.State);
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
        Assert.Equal((DownloadStates.Waiting, DownloadReasons.SearchFailed, (DateTimeOffset?)(T0 + DownloadService.CycleInterval)), (entry.State, entry.Reason, entry.NextSearchAt));

        // Si riprova al giro dopo.
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
    }

    [Fact]
    public async Task ASearchWithoutAnAnswerIsRetriedAfterADay()
    {
        _movies = [Movie(12)];
        _arr.Releases = (_, _) => Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable) { TimedOut = true });

        await Cycle();

        Assert.Equal(ArrClient.CycleSearchTimeout, _arr.LastReleaseTimeout);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, DownloadReasons.SearchFailed, (DateTimeOffset?)(T0 + DownloadSchedule.TimedOutPace)), (entry.State, entry.Reason, entry.NextSearchAt));

        // Al giro dopo non si ripete: Sonarr la sta ancora portando avanti.
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Single(_arr.SearchReleaseCalls);

        _time.Advance(DownloadSchedule.TimedOutPace - DownloadService.CycleInterval);
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
        Assert.Equal(T0 + DownloadService.CycleInterval, entry.NextSearchAt);
        Assert.Empty(Store().Load().Choices);
    }

    [Fact]
    public async Task ARefusedGrabGoesToNeedsYouAndIsNotGrabbedAgain()
    {
        _movies = [Movie(12)];
        _releases = [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)];
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.GrabRefused), (entry.State, entry.Reason));
        Assert.Equal(T0 + DownloadService.CycleInterval, entry.NextSearchAt);

        // Al giro dopo si cerca, ma la release rifiutata non si sceglie più.
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Single(_arr.GrabCalls);
    }

    [Fact]
    public async Task ARefusedUpgradeGrabKeepsTheUpgradeWatch()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150)];
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, DownloadReasons.GrabRefused), (entry.State, entry.Reason));
        Assert.Equal(_time.GetUtcNow() + DownloadService.CycleInterval, entry.NextSearchAt);
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

    [Fact]
    public async Task AFailingSearchDoesNotStarveOthers()
    {
        _movies = [.. Enumerable.Range(1, 12).Select(id => (RadarrMovie?)Movie(id))];
        _arr.Releases = (_, query) => query is "movieId=1" or "movieId=2"
            ? Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable))
            : Task.FromResult<IReadOnlyList<ArrRelease?>>([]);

        await Cycle();
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();

        var queries = _arr.SearchReleaseCalls.Select(c => c.Query).ToList();
        Assert.All(Enumerable.Range(3, 10), id => Assert.Contains($"movieId={id}", queries));

        // Nel secondo giro prima le voci mai cercate, poi quelle in errore.
        Assert.Equal(["movieId=11", "movieId=12", "movieId=1", "movieId=2"], queries.Skip(10));
    }

    [Fact]
    public async Task AFailedUpgradeKeepsTheOldScore()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        await StartUpgrade(Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150));

        // Esce dalla coda ma Radarr non dà il file: si aspetta il giro dopo.
        _arr.MovieFiles = _ => Task.FromException<IReadOnlyList<ArrFile?>>(new ArrException(ArrError.Unreachable));
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);

        // Il file è ancora quello di prima: l'upgrade è fallito.
        _arr.MovieFiles = ids => Task.FromResult<IReadOnlyList<ArrFile?>>([File(ids[0], WebRip1080, 50)]);
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();

        Assert.Equal([512], _arr.MovieFileCalls[^1]);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)50, (int?)WebRip1080, (int?)null), (entry.State, entry.CurrentScore, entry.CurrentQualityId, entry.PreviousScore));
        Assert.Equal(T0 + DownloadSchedule.UpgradeWindow, entry.UpgradeUntil);
        Assert.Equal(_time.GetUtcNow() + TimeSpan.FromHours(6), entry.NextSearchAt);
        Assert.Equal((long?)(4 * Gb), entry.CurrentSizeBytes);

        // L'upgrade dopo confronta con il file su disco (4 GB), non con quello fallito (5 GB).
        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ita-eng-2", WebRip1080, "WEBRip-1080p", 6, 150)];
        await Cycle();
        var choice = Store().Load().Choices[0];
        Assert.Equal(("ita-eng-2", (int?)50, (long?)(4 * Gb)), (choice.Guid, choice.PreviousScore, choice.PreviousSizeBytes));
    }

    [Fact]
    public async Task AFailedUpgradeWithAHeavierOldFileIsStillFailed()
    {
        // PreviousSizeBytes è il peso della release scelta (4 GB), il file vero pesa 6 GB: senza tappabuchi conta solo il punteggio.
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        await StartUpgrade(Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150));

        var old = File(512, WebRip1080, 50);
        old.Size = 6 * Gb;
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([old]);
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (long?)(4 * Gb), T0 + DownloadSchedule.UpgradeWindow), (entry.State, entry.CurrentSizeBytes, entry.UpgradeUntil));
    }

    [Fact]
    public async Task AnImportedUpgradeIsConfirmedByTheFile()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        await StartUpgrade(Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150));

        _fileScore = 150;
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [];
        await Cycle();

        // All'obiettivo: la voce esce.
        Assert.Single(_arr.MovieFileCalls);
        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task AStalledUpgradeGoesBackToUpgradeWatch()
    {
        await GrabAndImport(Release("ita", WebRip1080, "WEBRip-1080p", 4, 50));
        await StartUpgrade(Release("ita-eng", WebRip1080, "WEBRip-1080p", 5, 150));

        _time.Advance(DownloadSchedule.StalledAfter);
        await Cycle();

        Assert.Equal((ArrKind.Radarr, 91, true, true), Assert.Single(_arr.RemoveFromQueueCalls));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)50, (int?)null), (entry.State, entry.CurrentScore, entry.QueueId));
        Assert.Equal(T0 + DownloadSchedule.UpgradeWindow, entry.UpgradeUntil);
    }

    [Fact]
    public async Task AFailedEpisodeUpgradeKeepsTheOldScore()
    {
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];
        _releases = [Release("ep", WebRip1080, "WEBRip-1080p", 1, 50)];
        await Cycle();
        _releases = [];

        // Importato: Sonarr lo toglie dai mancanti.
        _missing = [];
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("episode:34")!.State);

        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Release("ep-ita-eng", WebRip1080, "WEBRip-1080p", 1.5, 150)];
        await Cycle();
        _releases = [];
        Assert.Equal(2, _arr.GrabCalls.Count);

        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([new SonarrEpisode { Id = 33, EpisodeFileId = 801 }, new SonarrEpisode { Id = 34, EpisodeFileId = 800 }]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([File(801, WebRip1080, 150), File(800, WebRip1080, 50)]);
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();

        // Il primo 7 è del primo giro: la serie si legge per vedere se la stagione è intera (Task 8).
        Assert.Equal([7, 7], _arr.SeriesEpisodeCalls);
        Assert.Equal([7], _arr.EpisodeFileCalls);
        var entry = Saved("episode:34")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)50), (entry.State, entry.CurrentScore));
    }

    [Fact]
    public async Task ACancelledCycleKeepsItsGrabs()
    {
        using var cancel = new CancellationTokenSource();
        _movies = [Movie(12), Movie(13), Movie(14)];
        string? stateDuringTheSecondSearch = null;
        _arr.Releases = (_, query) =>
        {
            if (query == "movieId=13")
            {
                // Già su disco prima della fine del giro; poi il giro si interrompe nella pausa che segue.
                stateDuringTheSecondSearch = Saved("movie:12")?.State;
                cancel.Cancel();
            }

            IReadOnlyList<ArrRelease?> releases = query == "movieId=12" ? [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)] : [];
            return Task.FromResult(releases);
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => _service.RunCycleAsync(cancel.Token));

        Assert.Equal(DownloadStates.Downloading, stateDuringTheSecondSearch);
        var restarted = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        restarted.Load();
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (int?)150), (entry.State, entry.CurrentScore));
        Assert.Equal("ita", Assert.Single(Store().Load().Choices).Guid);
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);

        // La ricerca di 13 (niente trovato) la salva solo il salvataggio di fine giro, anche se interrotto.
        Assert.Equal(T0, Saved("movie:13")!.LastSearchAt);
    }

    [Fact]
    public async Task AnEntryTakenMeanwhileIsNotGrabbed()
    {
        _movies = [Movie(12)];
        _arr.Releases = async (_, _) =>
        {
            // Durante la ricerca il titolo entra in coda (un giro nel frattempo lo segna Downloading).
            _radarrQueue = [MovieQueue(90, 12, 5_000)];
            await _service.RunCycleAsync(CancellationToken.None);
            return [Release("ita", WebRip1080, "WEBRip-1080p", 4, 150)];
        };

        var report = await Cycle();

        Assert.Equal(0, report.Grabbed);
        Assert.Empty(_arr.GrabCalls);
        Assert.Empty(Store().Load().Choices);
        Assert.Equal((DownloadStates.Downloading, (int?)90), (Saved("movie:12")!.State, Saved("movie:12")!.QueueId));
    }
}
