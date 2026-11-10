using System.Text.Json;
using System.Text.Json.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>"Scarica subito": le righe di una serie (o un film) passano davanti nella coda del giro.</summary>
public sealed class DownloadServiceRushTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly List<DownloadService> _services = [];
    private readonly DownloadService _service;

    // Ogni ricerca di release resta aperta finché il test non completa la sua (nell'ordine delle chiamate).
    private readonly Lock _gatesLock = new();
    private readonly List<TaskCompletionSource<IReadOnlyList<ArrRelease?>>> _gates = [];

    private List<RadarrMovie?> _movies = [];
    private List<SonarrEpisode?> _missing = [];
    private List<SonarrEpisode?> _seriesEpisodes = [];
    private int _nudges;

    public DownloadServiceRushTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_seriesEpisodes);
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        _arr.Releases = Gated;
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);

        _service = NewService();
        _service.Nudged += () => Interlocked.Increment(ref _nudges);
    }

    public void Dispose()
    {
        foreach (var service in _services)
        {
            service.StopSearches();
        }

        _folder.Dispose();
    }

    private DownloadService NewService()
    {
        var service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        _services.Add(service);
        return service;
    }

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    // Con un limite: una regressione fa fallire il test invece di bloccarlo.
    private Task<CycleReport> Cycle() => _service.RunCycleAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));

    private Task<IReadOnlyList<ArrRelease?>> Gated(ArrKind kind, string query)
    {
        var gate = new TaskCompletionSource<IReadOnlyList<ArrRelease?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gatesLock)
        {
            _gates.Add(gate);
        }

        return gate.Task;
    }

    // La ricerca non risponde (non per tempo scaduto): la voce resta com'è, con la ricerca dopo tra 15 minuti.
    private static Task<IReadOnlyList<ArrRelease?>> Failing(ArrKind kind, string query) =>
        Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable));

    // La ricerca numero index (da 0, dopo Seed) finisce senza release.
    private void Finish(int index)
    {
        lock (_gatesLock)
        {
            _gates[index].SetResult([]);
        }
    }

    // La ricerca numero index finisce per tempo scaduto: una stagione si divide in episodi.
    private void TimeOut(int index)
    {
        lock (_gatesLock)
        {
            _gates[index].SetException(new ArrException(ArrError.Unreachable) { TimedOut = true });
        }
    }

    // Le ricerche girano anche in altri thread: si aspetta la chiamata, poi si conta.
    private async Task<(ArrKind Kind, string Query)> Call(int index)
    {
        for (var i = 0; i < 500 && _arr.SearchReleaseCalls.Count <= index; i++)
        {
            await Task.Delay(10);
        }

        Assert.True(_arr.SearchReleaseCalls.Count > index, $"ricerca {index}");
        return _arr.SearchReleaseCalls[index];
    }

    private async Task<DownloadSearchStatusDto> Finished(string key)
    {
        for (var i = 0; i < 500; i++)
        {
            var status = _service.SearchStatus(key)!;
            if (status.State != DownloadSearchStates.Running)
            {
                return status;
            }

            await Task.Delay(10);
        }

        throw new TimeoutException(key);
    }

    private async Task<DownloadItemDto> Item(string key) =>
        (await _service.OverviewAsync(CancellationToken.None)).Waiting.Single(i => i.Key == key);

    // Un giro con le ricerche che falliscono crea le voci senza toccarle; poi passa un giorno: tutte sono scadute,
    // e un Rush da adesso ha un RushAt dopo il NextSearchAt delle altre. Le ricerche tornano ad aspettare il test.
    private async Task Seed()
    {
        _arr.Releases = Failing;
        await Cycle();
        _arr.SearchReleaseCalls.Clear();
        _arr.Releases = Gated;
        _time.Advance(TimeSpan.FromDays(1));
    }

    // Le voci come le vuole il test, senza un giro (il libro si legge alla prima occasione).
    private void Inject(params DownloadEntry[] entries)
    {
        var book = new DownloadBook();
        foreach (var entry in entries)
        {
            book.Put(entry);
        }

        Store().Save(book);
    }

    private static DownloadEntry Row(string key, string state = DownloadStates.Waiting, int seriesId = 7, DateTimeOffset? rushAt = null) => new()
    {
        Key = key,
        Kind = key.StartsWith("movie", StringComparison.Ordinal) ? DownloadKinds.Movie : key.StartsWith("season", StringComparison.Ordinal) ? DownloadKinds.Season : DownloadKinds.Episode,
        Title = key,
        State = state,
        ProfileId = key.StartsWith("movie", StringComparison.Ordinal) ? 4 : 6,
        RuntimeMinutes = 50,
        SeriesId = key.StartsWith("movie", StringComparison.Ordinal) ? 0 : seriesId,
        AvailableSince = T0 - TimeSpan.FromDays(3),
        NextSearchAt = T0,
        RushAt = rushAt,
    };

    private static SonarrEpisode SeasonEp(int id, int season)
    {
        var episode = Episode(id, T0 - TimeSpan.FromDays(30));
        episode.SeasonNumber = season;
        return episode;
    }

    private static SonarrEpisode Aired(int id) => Episode(id, T0 - TimeSpan.FromDays(1));

    [Fact]
    public async Task RushBringsTheWholeSeriesToTheFront()
    {
        _movies = [Movie(1)];
        _missing = [Aired(34), Aired(35)];
        await Seed();

        Assert.True(_service.Rush("episode:34"));
        _arr.Releases = Failing;
        await Cycle();

        Assert.Equal([ArrKind.Sonarr, ArrKind.Sonarr, ArrKind.Radarr], _arr.SearchReleaseCalls.Select(c => c.Kind));
    }

    [Fact]
    public async Task RushOnAMovieTouchesOnlyThatMovie()
    {
        _movies = [Movie(1), Movie(2)];
        await Seed();

        Assert.True(_service.Rush("movie:1"));

        var (one, two) = (await Item("movie:1"), await Item("movie:2"));
        Assert.Equal((true, true, true), (one.Rush, one.CanRush, two.CanRush));
        Assert.False(two.Rush);
        Assert.Null(one.SeriesId);

        // Sempre presenti nel JSON, anche SeriesId senza valore.
        var json = JsonSerializer.Serialize(one, Json);
        Assert.Contains("\"SeriesId\":null", json);
        Assert.Contains("\"CanRush\":true", json);
        Assert.Contains("\"Rush\":true", json);
    }

    [Fact]
    public async Task RushSkipsUpgradeWatchAndImportBlocked()
    {
        var blocked = Row("episode:36", DownloadStates.NeedsYou);
        blocked.Reason = DownloadReasons.ImportBlocked;
        var upgrade = Row("episode:35", DownloadStates.UpgradeWatch);
        upgrade.NextSearchAt = T0 + TimeSpan.FromDays(1);
        Inject(Row("episode:34"), upgrade, blocked);

        Assert.True(_service.Rush("episode:34"));

        var (waiting, watching, stuck) = (await Item("episode:34"), await Item("episode:35"), await Item("episode:36"));
        Assert.Equal((true, true), (waiting.CanRush, waiting.Rush));
        Assert.Equal((false, false), (watching.CanRush, watching.Rush));
        Assert.Equal((false, false), (stuck.CanRush, stuck.Rush));

        // Il ritmo di queste righe non cambia.
        Assert.Equal(T0 + TimeSpan.FromDays(1), watching.NextSearchAt);
        Assert.Equal(T0, stuck.NextSearchAt);
        Assert.True(_service.Rush("episode:35"));
    }

    [Fact]
    public async Task RushIncludesSnoozedAndNeedsYouRows()
    {
        var snoozed = Row("episode:34");
        snoozed.Snoozed = true;
        var needsYou = Row("episode:35", DownloadStates.NeedsYou);
        needsYou.Reason = DownloadReasons.NothingFound;
        Inject(snoozed, needsYou);

        Assert.True(_service.Rush("episode:34"));

        Assert.True((await Item("episode:34")).Rush);
        Assert.True((await Item("episode:35")).Rush);
    }

    [Fact]
    public void RushOfAnUnknownKeyIsFalse()
    {
        Assert.False(_service.Rush("movie:999"));
        Assert.False(_service.Rush("x"));
    }

    [Fact]
    public async Task RushWithNothingToRushDoesNotStopTheCycle()
    {
        _movies = [Movie(1), Movie(2), Movie(50, hasFile: true)];
        var upgrade = Row("movie:50", DownloadStates.UpgradeWatch);
        upgrade.UpgradeUntil = T0 + TimeSpan.FromDays(20);
        upgrade.NextSearchAt = T0 + TimeSpan.FromDays(1);
        Inject(upgrade);

        var cycle = Cycle();
        await Call(0);
        Assert.True(_service.Rush("movie:50"));
        Finish(0);
        await Call(1);
        Finish(1);

        Assert.Equal(2, (await cycle).Searched);
        Assert.Equal(0, Volatile.Read(ref _nudges));
    }

    [Fact]
    public async Task RushOfAnEntryWithoutSeriesIdTouchesOnlyIt()
    {
        Inject(Row("episode:34", seriesId: 0), Row("episode:35", seriesId: 0));

        Assert.True(_service.Rush("episode:34"));

        Assert.True((await Item("episode:34")).Rush);
        Assert.False((await Item("episode:35")).Rush);
    }

    // Tre film da cercare, la ricerca del primo in corso: il Rush del terzo ferma il giro dopo di lei.
    private async Task<CycleReport> RushMovie3WhileSearching()
    {
        _movies = [Movie(1), Movie(2), Movie(3)];
        var cycle = Cycle();
        Assert.Equal("movieId=1", (await Call(0)).Query);

        Assert.True(_service.Rush("movie:3"));
        Finish(0);
        return await cycle;
    }

    [Fact]
    public async Task ARunningCycleStopsAfterTheSearchInFlight()
    {
        var report = await RushMovie3WhileSearching();

        Assert.Equal(1, report.Searched);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.True(Volatile.Read(ref _nudges) >= 1);
    }

    [Fact]
    public async Task TheNextCycleStartsFromTheRushedRow()
    {
        await RushMovie3WhileSearching();

        var cycle = Cycle();
        Assert.Equal("movieId=3", (await Call(1)).Query);
        Finish(1);
        Assert.Equal("movieId=2", (await Call(2)).Query);
        Finish(2);

        Assert.Equal(2, (await cycle).Searched);
    }

    [Fact]
    public async Task TheCapOfTenDoesNotApplyToRushedRows()
    {
        _movies = [.. Enumerable.Range(1, 15).Select(id => (RadarrMovie?)Movie(id))];
        await Seed();
        for (var id = 1; id <= 12; id++)
        {
            Assert.True(_service.Rush($"movie:{id}"));
        }

        _arr.Releases = Failing;
        var report = await Cycle();

        Assert.Equal(12, report.Searched);
        Assert.Equal(
            Enumerable.Range(1, 12).Select(id => $"movieId={id}").Order(StringComparer.Ordinal),
            _arr.SearchReleaseCalls.Select(c => c.Query).Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task RushAtIsClearedAfterTheSearchWhateverTheOutcome()
    {
        _movies = [Movie(1), Movie(2)];
        await Seed();
        Assert.True(_service.Rush("movie:1"));
        Assert.True(_service.Rush("movie:2"));

        // Il film 1 senza release, la ricerca del 2 che lancia.
        _arr.Releases = (_, query) => query == "movieId=2" ? Failing(ArrKind.Radarr, query) : Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        await Cycle();

        foreach (var key in new[] { "movie:1", "movie:2" })
        {
            var entry = Saved(key)!;
            Assert.Null(entry.RushAt);
            Assert.True(entry.NextSearchAt > _time.GetUtcNow(), key);
            Assert.False((await Item(key)).Rush);
        }
    }

    [Fact]
    public async Task RushAtIsClearedWhenTheRowLeavesTheRushableStates()
    {
        _movies = [Movie(1)];
        await Seed();
        Assert.True(_service.Rush("movie:1"));

        // Radarr l'ha già in coda: la riga scarica, non c'è più nulla da anticipare.
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? [MovieQueue(91, 1, 5_000)] : []);
        await Cycle();

        var entry = Saved("movie:1")!;
        Assert.Equal(DownloadStates.Downloading, entry.State);
        Assert.Null(entry.RushAt);
    }

    [Fact]
    public async Task ManualSearchesStillComeFirst()
    {
        _movies = [Movie(1), Movie(2), Movie(50, hasFile: true)];
        await Seed();
        Assert.True(_service.Rush("movie:2"));

        _service.StartSearch("movie:50", false);
        await Call(0);

        // La ricerca dell'admin è in corso: il giro non cerca, nemmeno la riga con la precedenza.
        Assert.Equal(0, (await Cycle()).Searched);
        Assert.Single(_arr.SearchReleaseCalls);

        Finish(0);
        await Finished("movie:50");

        // Alla ripresa la riga con la precedenza è la prima.
        var cycle = Cycle();
        Assert.Equal("movieId=2", (await Call(1)).Query);
        Finish(1);
        Assert.Equal("movieId=1", (await Call(2)).Query);
        Finish(2);
        Assert.Equal(2, (await cycle).Searched);
    }

    [Fact]
    public async Task RushedRowsGoInSeasonOrderWithinARush()
    {
        // "Stagione 10" prima nell'elenco: senza l'ordine per lunghezza del titolo verrebbe cercata per prima.
        _seriesEpisodes = [SeasonEp(210, 10), SeasonEp(202, 2)];
        _missing = [.. _seriesEpisodes];
        await Seed();

        Assert.True(_service.Rush("season:7:2"));
        _arr.Releases = Failing;
        await Cycle();

        Assert.Equal(["seriesId=7&seasonNumber=2", "seriesId=7&seasonNumber=10"], _arr.SearchReleaseCalls.Select(c => c.Query));
    }

    [Fact]
    public async Task SplittingARushedSeasonKeepsThePrecedence()
    {
        _movies = [Movie(1)];
        _seriesEpisodes = [SeasonEp(201, 2), SeasonEp(202, 2), SeasonEp(203, 2)];
        _missing = [.. _seriesEpisodes];
        await Seed();
        Assert.True(_service.Rush("season:7:2"));
        Interlocked.Exchange(ref _nudges, 0);

        // La stagione non risponde in tempo: si divide. Il film, scaduto anche lui, non si cerca: il giro si ferma.
        _arr.Releases = (kind, query) => kind == ArrKind.Sonarr
            ? Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable) { TimedOut = true })
            : Failing(kind, query);
        var report = await Cycle();

        Assert.Equal(1, report.Searched);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.True(Volatile.Read(ref _nudges) >= 1);
        foreach (var key in new[] { "episode:201", "episode:202", "episode:203" })
        {
            Assert.NotNull(Saved(key)!.RushAt);
            Assert.True((await Item(key)).Rush);
        }

        Assert.Null(Saved("season:7:2"));
    }

    [Fact]
    public async Task ASplitWithoutRushAtKeepsAPendingStopRequest()
    {
        // Due serie con la stagione 2 intera da cercare: la 7 per prima, la 8 dopo.
        var other = new[] { SeasonEp(301, 2), SeasonEp(302, 2), SeasonEp(303, 2) };
        foreach (var episode in other)
        {
            episode.SeriesId = 8;
        }

        _seriesEpisodes = [SeasonEp(201, 2), SeasonEp(202, 2), SeasonEp(203, 2), .. other];
        _missing = [.. _seriesEpisodes];
        _arr.SeriesEpisodes = id => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([.. _seriesEpisodes.Where(e => e?.SeriesId == id)]);
        await Seed();

        var cycle = Cycle();
        Assert.Equal("seriesId=7&seasonNumber=2", (await Call(0)).Query);

        // L'admin anticipa l'altra serie mentre la 7 (senza precedenza) cerca; poi la 7 si divide: la richiesta di fermarsi resta.
        Assert.True(_service.Rush("season:8:2"));
        TimeOut(0);

        Assert.Equal(1, (await cycle).Searched);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Null(Saved("season:7:2"));
        Assert.NotNull(Saved("episode:201"));
    }

    [Fact]
    public async Task GroupingRushedEpisodesKeepsTheOldestRushAt()
    {
        _movies = [Movie(1)];
        _seriesEpisodes = [SeasonEp(201, 2), SeasonEp(202, 2), SeasonEp(203, 2)];
        _missing = [.. _seriesEpisodes];

        // Un episodio senza precedenza, due con: la stagione prende la più vecchia (T0), non la prima né la più recente.
        // Il film, con la precedenza a metà strada, deve venire dopo la stagione.
        Inject(
            Row("episode:201", rushAt: T0 + TimeSpan.FromHours(1)),
            Row("episode:202", rushAt: T0),
            Row("episode:203"),
            Row("movie:1", rushAt: T0 + TimeSpan.FromMinutes(30)));
        _arr.Releases = Failing;
        await Cycle();

        Assert.Equal([(ArrKind.Sonarr, "seriesId=7&seasonNumber=2"), (ArrKind.Radarr, "movieId=1")], _arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task RefreshReadsTheListWithoutSearching()
    {
        _movies = [Movie(1)];

        _service.Refresh();
        var report = await Cycle();

        Assert.Equal(0, report.Searched);
        Assert.Empty(_arr.SearchReleaseCalls);
        Assert.NotNull(Saved("movie:1"));
        Assert.False((await _service.OverviewAsync(CancellationToken.None)).RefreshPending);
    }

    [Fact]
    public async Task RefreshPendingIsTrueUntilTheListIsRead()
    {
        Assert.False((await _service.OverviewAsync(CancellationToken.None)).RefreshPending);

        _service.Refresh();

        Assert.True((await _service.OverviewAsync(CancellationToken.None)).RefreshPending);
        Assert.True(_service.UrgentCycleWanted);
    }

    [Fact]
    public async Task RefreshDuringACycleStopsItAndReadsNext()
    {
        _movies = [Movie(1), Movie(2)];
        var cycle = Cycle();
        await Call(0);

        _service.Refresh();
        Finish(0);

        Assert.Equal(1, (await cycle).Searched);
        Assert.True((await _service.OverviewAsync(CancellationToken.None)).RefreshPending);

        Assert.Equal(0, (await Cycle()).Searched);
        Assert.False((await _service.OverviewAsync(CancellationToken.None)).RefreshPending);
        Assert.Single(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task ARefreshCycleSearchesIfARowIsRushed()
    {
        _movies = [Movie(1), Movie(2)];
        await Seed();
        Assert.True(_service.Rush("movie:2"));
        _service.Refresh();

        _arr.Releases = Failing;
        var report = await Cycle();

        Assert.Equal((ArrKind.Radarr, "movieId=2"), _arr.SearchReleaseCalls[0]);
        Assert.True(report.Searched >= 1);
    }

    [Fact]
    public async Task TheCycleAfterARefreshSearchesNormally()
    {
        _movies = [Movie(1)];
        _service.Refresh();
        await Cycle();

        _arr.Releases = Failing;
        Assert.True((await Cycle()).Searched > 0);
    }

    [Fact]
    public async Task RushAtSurvivesARestart()
    {
        _movies = [Movie(1), Movie(2)];
        await Seed();
        Assert.True(_service.Rush("movie:2"));

        _arr.Releases = Failing;
        await NewService().RunCycleAsync(CancellationToken.None);

        Assert.Equal((ArrKind.Radarr, "movieId=2"), _arr.SearchReleaseCalls[0]);
    }
}
