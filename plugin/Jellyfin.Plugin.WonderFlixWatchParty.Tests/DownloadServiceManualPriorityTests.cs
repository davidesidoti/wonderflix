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

/// <summary>Le ricerche dell'admin hanno la precedenza su quelle del giro e vanno da sole (dalla 1.26.0).</summary>
public sealed class DownloadServiceManualPriorityTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private static readonly JsonSerializerOptions Json = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    // Ogni ricerca di release resta aperta finché il test non completa la sua (nell'ordine delle chiamate).
    private readonly Lock _gatesLock = new();
    private readonly List<TaskCompletionSource<IReadOnlyList<ArrRelease?>>> _gates = [];

    private List<RadarrMovie?> _movies = [];
    private List<SonarrEpisode?> _missing = [];
    private int _nudges;

    public DownloadServiceManualPriorityTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        _arr.Releases = Gated;
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);

        _service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        _service.Nudged += () => Interlocked.Increment(ref _nudges);
    }

    public void Dispose()
    {
        _service.StopSearches();
        _folder.Dispose();
    }

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private Task<CycleReport> Cycle() => _service.RunCycleAsync(CancellationToken.None);

    private Task<IReadOnlyList<ArrRelease?>> Gated(ArrKind kind, string query)
    {
        var gate = new TaskCompletionSource<IReadOnlyList<ArrRelease?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gatesLock)
        {
            _gates.Add(gate);
        }

        return gate.Task;
    }

    // La ricerca numero index (da 0) finisce senza release.
    private void Finish(int index)
    {
        lock (_gatesLock)
        {
            _gates[index].SetResult([]);
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

    private async Task<SearchProgressDto?> Progress() => (await _service.OverviewAsync(CancellationToken.None)).Progress;

    // Una ricerca del giro in corso su un film che dura duration: si aspetta che parta, poi finisce dopo duration.
    private async Task AutoSearch(int index, TimeSpan duration)
    {
        await Call(index);
        _time.Advance(duration);
        Finish(index);
    }

    [Fact]
    public async Task AManualSearchWaitsForTheAutomaticOneInFlight()
    {
        _movies = [Movie(1, title: "Uno"), Movie(2, title: "Due")];
        var cycle = Cycle();
        var auto = await Call(0);
        var (autoKey, otherKey, autoTitle) = auto.Query == "movieId=1" ? ("movie:1", "movie:2", "Uno (2021)") : ("movie:2", "movie:1", "Due (2021)");

        _time.Advance(TimeSpan.FromSeconds(30));
        var waiting = _service.StartSearch(otherKey, false)!;

        Assert.Equal((DownloadSearchStates.Running, (DateTimeOffset?)(T0 + TimeSpan.FromSeconds(30))), (waiting.State, waiting.StartedAt));
        Assert.Equal(new SearchWaitDto(autoTitle, T0, null), waiting.WaitingFor);
        Assert.Equal(waiting.WaitingFor, _service.SearchStatus(otherKey)!.WaitingFor);
        Assert.Single(_arr.SearchReleaseCalls);

        // La ricerca del giro finisce: parte quella dell'admin, il giro non cerca altro.
        _time.Advance(TimeSpan.FromSeconds(20));
        Finish(0);
        Assert.Equal(1, (await cycle).Searched);
        Assert.Equal("movieId=" + otherKey[6..], (await Call(1)).Query);

        var running = _service.SearchStatus(otherKey)!;
        Assert.Equal((DownloadSearchStates.Running, (DateTimeOffset?)(T0 + TimeSpan.FromSeconds(50)), (SearchWaitDto?)null), (running.State, running.StartedAt, running.WaitingFor));

        Finish(1);
        var done = await Finished(otherKey);
        Assert.Equal(DownloadSearchStates.Done, done.State);
        Assert.Null(done.WaitingFor);
        Assert.Contains("\"WaitingFor\":null", JsonSerializer.Serialize(done, Json));
        Assert.NotEqual(autoKey, otherKey);
    }

    [Fact]
    public async Task TheCycleHoldsDuringAManualSearchAndResumesAfterIt()
    {
        _movies = [Movie(1), Movie(50, hasFile: true)];
        _missing = [Episode(34, T0 - TimeSpan.FromDays(1))];

        _service.StartSearch("movie:50", false);
        await Call(0);

        // Né Radarr né Sonarr: il giro crea le voci ma non cerca.
        Assert.Equal(0, (await Cycle()).Searched);
        Assert.Single(_arr.SearchReleaseCalls);

        var progress = (await Progress())!;
        Assert.Equal((2, true, (DateTimeOffset?)null), (progress.Remaining, progress.ManualSearch, progress.EstimatedEnd));
        Assert.Contains("\"ManualSearch\":true", JsonSerializer.Serialize(progress, Json));
        Assert.Equal(0, Volatile.Read(ref _nudges));

        // Finita la ricerca dell'admin si chiede subito un giro, che cerca di nuovo.
        Finish(0);
        await Finished("movie:50");
        Assert.Equal(1, Volatile.Read(ref _nudges));
        Assert.False((await Progress())!.ManualSearch);

        var cycle = Cycle();
        await AutoSearch(1, TimeSpan.Zero);
        await AutoSearch(2, TimeSpan.Zero);
        Assert.Equal(2, (await cycle).Searched);
        Assert.Equal([ArrKind.Radarr, ArrKind.Sonarr], _arr.SearchReleaseCalls.Skip(1).Select(c => c.Kind).OrderBy(k => k.ToString()));
    }

    [Fact]
    public async Task WithoutAHeldCycleTheEndOfAManualSearchDoesNotNudge()
    {
        _movies = [Movie(50, hasFile: true)];

        _service.StartSearch("movie:50", false);
        await Call(0);
        Finish(0);
        await Finished("movie:50");

        Assert.Equal(0, Volatile.Read(ref _nudges));
    }

    [Fact]
    public async Task TheTypicalDurationIsTheAverageOfTheLastTenAutomaticSearches()
    {
        _movies = [.. Enumerable.Range(1, 14).Select(id => (RadarrMovie?)Movie(id)), Movie(50, hasFile: true)];

        // Due ricerche finite (10 e 20 s), la terza in corso: nessuna durata tipica.
        var cycle = Cycle();
        await AutoSearch(0, TimeSpan.FromSeconds(10));
        await AutoSearch(1, TimeSpan.FromSeconds(20));
        await Call(2);
        Assert.Null(_service.StartSearch("movie:50", false)!.WaitingFor!.TypicalSeconds);
        _time.Advance(TimeSpan.FromSeconds(30));
        Finish(2);
        Assert.Equal(3, (await cycle).Searched);
        await Call(3);
        Finish(3);
        await Finished("movie:50");

        // Altre 10 (40..130 s): la media delle ultime 10, senza le prime tre, è 85.
        cycle = Cycle();
        for (var i = 4; i < 14; i++)
        {
            await AutoSearch(i, TimeSpan.FromSeconds(i * 10));
        }

        Assert.Equal(10, (await cycle).Searched);

        cycle = Cycle();
        await Call(14);
        Assert.Equal(85, _service.StartSearch("movie:50", true)!.WaitingFor!.TypicalSeconds);
        Finish(14);
        await cycle;
        await Call(15);
        Finish(15);
        await Finished("movie:50");
    }

    // Il film 1 da cercare e Animals (12) in "Serve te" sotto il minimo, con "Scarica il migliore intanto".
    private void AnimalsNeedsYou()
    {
        _movies = [Movie(1), Movie(12, title: "Animals", year: 2025, runtime: 106)];
        var book = new DownloadBook();
        book.Put(new DownloadEntry
        {
            Key = "movie:12",
            Kind = DownloadKinds.Movie,
            Title = "Animals (2025)",
            State = DownloadStates.NeedsYou,
            Reason = DownloadReasons.BelowMinScore,
            ProfileId = 4,
            RuntimeMinutes = 106,
            AvailableSince = T0 - TimeSpan.FromDays(10),
            NextSearchAt = T0 + TimeSpan.FromDays(1),
        });
        Store().Save(book);
    }

    [Fact]
    public async Task GrabBestIsAManualSearch()
    {
        AnimalsNeedsYou();

        var grab = _service.GrabBestAsync("movie:12");
        await Call(0);

        Assert.Equal(0, (await Cycle()).Searched);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.True((await Progress())!.ManualSearch);

        Finish(0);
        Assert.Equal(GrabOutcome.NothingToGrab, await grab);
        Assert.Equal(1, Volatile.Read(ref _nudges));
        Assert.False((await Progress())!.ManualSearch);
    }

    [Fact]
    public async Task GrabBestWaitsForTheAutomaticSearchInFlight()
    {
        AnimalsNeedsYou();

        var cycle = Cycle();
        Assert.Equal("movieId=1", (await Call(0)).Query);
        var grab = _service.GrabBestAsync("movie:12");
        Assert.True((await Progress())!.ManualSearch);
        Assert.Single(_arr.SearchReleaseCalls);

        Finish(0);
        await cycle;
        Assert.Equal("movieId=12", (await Call(1)).Query);
        Finish(1);
        Assert.Equal(GrabOutcome.NothingToGrab, await grab);
    }
}
