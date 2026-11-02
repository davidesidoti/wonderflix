using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Le ricerche dell'admin in background (spec W §4.2-4.4, §4.7).</summary>
public sealed class DownloadServiceSearchJobTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    // Il cancello tiene aperta la ricerca di release: ogni apertura ne lascia passare una.
    private readonly SemaphoreSlim _gate = new(0);

    private List<RadarrMovie?> _movies = [];
    private List<ArrRelease?> _releases = [];

    public DownloadServiceSearchJobTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        _arr.Releases = Gated;
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }, new ArrIndexer { Id = 3, Priority = 10 }]);

        _movies = [Movie(12, title: "Animals", year: 2025, runtime: 106)];
        _releases =
        [
            Release("a", WebDl1080, "WEBDL-1080p", 2.9, 150),
            Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3),
            Release("c", WebRip1080, "WEBRip-1080p", 4.83, 150),
            Release("d", WebRip1080, "WEBRip-1080p", 1.1, 150),
        ];

        _service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
    }

    public void Dispose()
    {
        _service.StopSearches();
        _gate.Dispose();
        _folder.Dispose();
    }

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private async Task<IReadOnlyList<ArrRelease?>> Gated(ArrKind kind, string query)
    {
        await _gate.WaitAsync();
        return _releases;
    }

    private void OpenGate() => _gate.Release();

    // Il job gira in un altro thread: si aspetta che finisca guardando lo stato.
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

    // Il job arriva alla ricerca di release in un altro thread: si aspetta la chiamata, poi si conta.
    private async Task SearchedTimes(int count)
    {
        for (var i = 0; i < 500 && _arr.SearchReleaseCalls.Count < count; i++)
        {
            await Task.Delay(10);
        }

        Assert.Equal(count, _arr.SearchReleaseCalls.Count);
    }

    private async Task<DownloadSearchStatusDto> StartedAndFinished(string key, bool again = false)
    {
        Assert.Equal(DownloadSearchStates.Running, _service.StartSearch(key, again)!.State);
        OpenGate();
        return await Finished(key);
    }

    [Fact]
    public async Task StartReturnsRunningAndSearchesInTheBackground()
    {
        var started = _service.StartSearch("movie:12", false)!;

        Assert.Equal(("movie:12", DownloadSearchStates.Running, (DateTimeOffset?)_time.GetUtcNow(), "Radarr"), (started.Key, started.State, started.StartedAt, started.Service));
        Assert.Null(started.Result);

        OpenGate();
        var done = await Finished("movie:12");

        Assert.Equal(DownloadSearchStates.Done, done.State);
        Assert.Equal(["b", "a", "c"], done.Result!.Candidates.Select(c => c.Release.Guid));
        Assert.Equal([true, false, false], done.Result.Candidates.Select(c => c.IsChoice));
        Assert.Null(done.Result.Error);
    }

    [Fact]
    public async Task TheCycleLeavesAloneAnEntryTheAdminIsSearching()
    {
        // Solo la prima ricerca, quella dell'admin, resta al cancello.
        _arr.Releases = (kind, query) => _arr.SearchReleaseCalls.Count == 1 ? Gated(kind, query) : Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _service.StartSearch("movie:12", false);
        await SearchedTimes(1);

        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Single(_arr.SearchReleaseCalls);

        OpenGate();
        await Finished("movie:12");
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
    }

    [Fact]
    public async Task ASecondStartJoinsTheRunningSearch()
    {
        _service.StartSearch("movie:12", false);
        Assert.Equal(DownloadSearchStates.Running, _service.StartSearch("movie:12", true)!.State);

        OpenGate();
        Assert.Equal(DownloadSearchStates.Done, (await Finished("movie:12")).State);
        Assert.Single(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task AFinishedSearchIsReusedForThirtyMinutes()
    {
        await StartedAndFinished("movie:12");

        var again = _service.StartSearch("movie:12", false)!;
        Assert.Equal(DownloadSearchStates.Done, again.State);
        Assert.Equal(["b", "a", "c"], again.Result!.Candidates.Select(c => c.Release.Guid));
        Assert.Single(_arr.SearchReleaseCalls);

        _time.Advance(TimeSpan.FromMinutes(31));
        Assert.Equal(DownloadSearchStates.None, _service.SearchStatus("movie:12")!.State);
        Assert.Equal(DownloadSearchStates.Running, _service.StartSearch("movie:12", false)!.State);
        await SearchedTimes(2);
    }

    [Fact]
    public async Task AgainStartsANewSearch()
    {
        await StartedAndFinished("movie:12");

        Assert.Equal(DownloadSearchStates.Running, _service.StartSearch("movie:12", true)!.State);
        await SearchedTimes(2);
    }

    [Fact]
    public async Task AnArrErrorIsDoneWithErrorAndIsNotRetriedOnReopen()
    {
        _arr.Releases = (_, _) => throw new ArrException(ArrError.Unreachable);

        _service.StartSearch("movie:12", false);
        var done = await Finished("movie:12");

        Assert.Equal((DownloadSearchStates.Done, (string?)UpcomingErrors.Unreachable), (done.State, done.Result!.Error));
        Assert.Empty(done.Result.Candidates);

        var reopened = _service.StartSearch("movie:12", false)!;
        Assert.Equal((DownloadSearchStates.Done, (string?)UpcomingErrors.Unreachable), (reopened.State, reopened.Result!.Error));
        Assert.Single(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task AMissingTitleIsMissing()
    {
        _service.StartSearch("movie:99", false);

        Assert.Equal(DownloadSearchStates.Missing, (await Finished("movie:99")).State);
        Assert.Null(_service.StartSearch("garbage", false));
        Assert.Null(_service.SearchStatus("garbage"));
        Assert.Empty(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task TheOldSearchWaitsAndItsCancellationDoesNotStopTheJob()
    {
        using var request = new CancellationTokenSource();
        var old = _service.SearchAsync("movie:12", request.Token);
        Assert.Equal(DownloadSearchStates.Running, _service.SearchStatus("movie:12")!.State);

        request.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => old);

        OpenGate();
        Assert.Equal(DownloadSearchStates.Done, (await Finished("movie:12")).State);
        Assert.False(_arr.LastReleaseToken.IsCancellationRequested);
    }

    [Fact]
    public async Task TheOldSearchAlwaysSearchesAgain()
    {
        await StartedAndFinished("movie:12");

        var old = _service.SearchAsync("movie:12", CancellationToken.None);
        OpenGate();
        var result = await old;

        Assert.Equal(["b", "a", "c"], result!.Candidates.Select(c => c.Release.Guid));
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
    }

    [Fact]
    public async Task TheOverviewShowsSearchingDuringAnAdminSearch()
    {
        // Il giro crea la voce del film.
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        await _service.RunCycleAsync(CancellationToken.None);
        _arr.Releases = Gated;

        _service.StartSearch("movie:12", false);
        Assert.Equal(DownloadSearchPhases.Searching, await PhaseOf("movie:12"));

        OpenGate();
        await Finished("movie:12");
        Assert.NotEqual(DownloadSearchPhases.Searching, await PhaseOf("movie:12"));
    }

    private async Task<string?> PhaseOf(string key) => (await _service.OverviewAsync(CancellationToken.None)).Waiting.Single(i => i.Key == key).SearchPhase;

    [Fact]
    public async Task StopSearchesCancelsTheJob()
    {
        _service.StartSearch("movie:12", false);

        await SearchedTimes(1);
        _service.StopSearches();

        Assert.True(_arr.LastReleaseToken.IsCancellationRequested);
    }
}
