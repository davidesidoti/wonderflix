using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I download fermi all'import senza serie né film: si vedono nella panoramica e si possono togliere, solo loro.</summary>
public sealed class DownloadServiceUnknownTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 2, 12, 0, 0, TimeSpan.Zero));
    private readonly DownloadService _service;
    private IReadOnlyList<ArrQueueItem?> _sonarr = [];
    private IReadOnlyList<ArrQueueItem?> _radarr = [];

    public DownloadServiceUnknownTests()
    {
        _arr.UnknownQueue = kind => Task.FromResult(kind == ArrKind.Sonarr ? _sonarr : _radarr);
        _service = TestDownloads.Create(_arr, _time, _folder.DownloadsFile);
    }

    public void Dispose() => _folder.Dispose();

    private static ArrQueueItem Unknown(int id, string? downloadId = "D1", string state = "importBlocked", string? status = "warning") => new()
    {
        Id = id,
        DownloadId = downloadId,
        Title = "Outlander 2015 S01",
        Size = 27_000,
        TrackedDownloadState = state,
        TrackedDownloadStatus = status,
        StatusMessages = [new ArrStatusMessage { Title = "x", Messages = ["Series title mismatch"] }],
    };

    private async Task<IReadOnlyList<UnknownDownloadDto>> Listed() => (await _service.OverviewAsync(CancellationToken.None)).Unknown;

    [Fact]
    public async Task TheOverviewListsABlockedDownloadWithoutATitle()
    {
        _radarr = [Unknown(2, "R1")];
        _sonarr = [Unknown(1)];

        Assert.Equal(
            [new UnknownDownloadDto("Sonarr", "D1", "Outlander 2015 S01", 27_000, "Series title mismatch"), new UnknownDownloadDto("Radarr", "R1", "Outlander 2015 S01", 27_000, "Series title mismatch")],
            await Listed());
    }

    [Fact]
    public async Task ADownloadWithManyItemsIsOneRow()
    {
        _sonarr = [Unknown(1), Unknown(2)];

        Assert.Single(await Listed());
    }

    [Fact]
    public async Task TheOverviewLeavesOutEverythingElse()
    {
        _sonarr =
        [
            Unknown(1, state: "downloading", status: "ok"),
            Unknown(2, "D2", state: "importPending", status: "ok"),
            Unknown(3, downloadId: null),
            new ArrQueueItem { Id = 4, DownloadId = "D4", SeriesId = 7, EpisodeId = 9, TrackedDownloadState = "importBlocked" },
            new ArrQueueItem { Id = 5, DownloadId = "D5", MovieId = 12, TrackedDownloadState = "importBlocked" },
            null,
        ];

        Assert.Empty(await Listed());
    }

    [Fact]
    public async Task ARejectedImportWithoutATitleIsListed()
    {
        _sonarr = [Unknown(1, state: "importPending", status: "warning")];

        Assert.Single(await Listed());
    }

    [Fact]
    public async Task ADownloadSharedWithATitleIsNeitherListedNorRemoved()
    {
        // Togliere l'elemento sconosciuto cancellerebbe anche i file del titolo: stesso torrent.
        _sonarr = [Unknown(1), new ArrQueueItem { Id = 2, DownloadId = "D1", SeriesId = 7, EpisodeId = 9, TrackedDownloadState = "importBlocked" }];

        Assert.Empty(await Listed());
        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task AFailedReadLeavesThatServiceEmptyWithoutAnError()
    {
        _radarr = [Unknown(2, "R1")];
        _arr.UnknownQueue = kind => kind == ArrKind.Sonarr
            ? Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable))
            : Task.FromResult(_radarr);

        var overview = await _service.OverviewAsync(CancellationToken.None);

        Assert.Equal("R1", Assert.Single(overview.Unknown).DownloadId);
        Assert.Null(overview.SonarrError);
    }

    [Fact]
    public async Task TheOverviewReadsOnceAMinute()
    {
        await Listed();
        await Listed();
        Assert.Equal(2, _arr.UnknownQueueCalls.Count);

        _time.Advance(TimeSpan.FromMinutes(1));
        await Listed();
        Assert.Equal(4, _arr.UnknownQueueCalls.Count);
    }

    [Fact]
    public async Task TheCycleNeverReadsTheUnknownItems()
    {
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(_arr.UnknownQueueCalls);
    }

    [Fact]
    public async Task RemoveDeletesFromTheClientWithoutBlocklistAndTheRowGoesAtOnce()
    {
        _sonarr = [Unknown(1), Unknown(2), Unknown(3, "D2")];
        Assert.Equal(2, (await Listed()).Count);

        Assert.Equal(BlockedOutcome.Ok, await _service.RemoveUnknownAsync("Sonarr", "D1"));

        Assert.Equal([(ArrKind.Sonarr, 1, false, true), (ArrKind.Sonarr, 2, false, true)], _arr.RemoveFromQueueCalls);

        _sonarr = [Unknown(3, "D2")];
        Assert.Equal("D2", Assert.Single(await Listed()).DownloadId);
    }

    [Fact]
    public async Task RemoveRereadsTheQueueInsteadOfTrustingTheList()
    {
        _sonarr = [Unknown(1)];
        Assert.Single(await Listed());

        // Nel frattempo Sonarr l'ha legato a una serie: non si tocca, anche se la riga era in elenco.
        _sonarr = [new ArrQueueItem { Id = 1, DownloadId = "D1", SeriesId = 7, EpisodeId = 9, TrackedDownloadState = "importBlocked" }];

        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Theory]
    [InlineData("downloading", "ok")]
    [InlineData("importPending", "ok")]
    public async Task RemoveLeavesADownloadThatIsNotBlocked(string state, string status)
    {
        _sonarr = [Unknown(1, state: state, status: status)];

        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task RemoveOnlyTouchesItsService()
    {
        _radarr = [Unknown(1)];

        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Equal(BlockedOutcome.Ok, await _service.RemoveUnknownAsync("Radarr", "D1"));
        Assert.Equal((ArrKind.Radarr, 1, false, true), Assert.Single(_arr.RemoveFromQueueCalls));
    }

    [Theory]
    [InlineData(null, "D1")]
    [InlineData("Sonarr", null)]
    [InlineData("Sonarr", " ")]
    [InlineData("0", "D1")]
    [InlineData("sonarr", "D1")]
    [InlineData("Lidarr", "D1")]
    public async Task RemoveRefusesAnInvalidRequest(string? service, string? downloadId)
    {
        _sonarr = [Unknown(1)];

        Assert.Equal(BlockedOutcome.Invalid, await _service.RemoveUnknownAsync(service, downloadId));
        Assert.Empty(_arr.UnknownQueueCalls);
    }

    [Fact]
    public async Task RemoveIsUnavailableIfTheServiceDoesNotAnswer()
    {
        _arr.UnknownQueue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));
        Assert.Equal(BlockedOutcome.Unavailable, await _service.RemoveUnknownAsync("Sonarr", "D1"));

        _arr.UnknownQueue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([Unknown(1)]);
        _arr.RemoveFromQueue = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable));
        Assert.Equal(BlockedOutcome.Unavailable, await _service.RemoveUnknownAsync("Sonarr", "D1"));
    }

    [Fact]
    public async Task RemoveRefusesADownloadThatHasATitleInTheOtherService()
    {
        // Categoria qBittorrent condivisa: il film legato in Radarr compare in Sonarr senza serie.
        _sonarr = [Unknown(1, "ABC")];
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(
            kind == ArrKind.Radarr ? [new ArrQueueItem { Id = 9, MovieId = 12, DownloadId = "abc" }] : []);

        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "ABC"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task RemoveChecksTheOtherServiceAlsoFromRadarr()
    {
        _radarr = [Unknown(1)];
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(
            kind == ArrKind.Sonarr ? [new ArrQueueItem { Id = 9, SeriesId = 7, EpisodeId = 3, DownloadId = "D1" }] : []);

        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Radarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task RemoveProceedsIfTheOtherServiceDoesNotHaveThatDownloadWithATitle()
    {
        _sonarr = [Unknown(1)];
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(
            [new ArrQueueItem { Id = 9, MovieId = 12, DownloadId = "Other" }, new ArrQueueItem { Id = 10, DownloadId = "D1" }, null]);

        Assert.Equal(BlockedOutcome.Ok, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Equal(ArrKind.Radarr, Assert.Single(_arr.QueueCalls));
        Assert.Single(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task RemoveIsUnavailableIfTheOtherServiceDoesNotAnswer()
    {
        _sonarr = [Unknown(1)];
        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));

        Assert.Equal(BlockedOutcome.Unavailable, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task RemoveProceedsIfTheOtherServiceIsNotConfigured()
    {
        _sonarr = [Unknown(1)];
        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.NotConfigured));
        var service = new DownloadService(
            _arr,
            new FakeArrSettings { Radarr = new ArrEndpoint(string.Empty, string.Empty) },
            new FakeDownloadSettings(),
            new DownloadStore(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance),
            _time,
            NullLogger<DownloadService>.Instance,
            null);

        Assert.Equal(BlockedOutcome.Ok, await service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.QueueCalls);
        Assert.Single(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task AHungServiceDoesNotHoldTheOverviewPastTheLimit()
    {
        var hung = new TaskCompletionSource<IReadOnlyList<ArrQueueItem?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _radarr = [Unknown(2, "R1")];
        _arr.UnknownQueue = kind => kind == ArrKind.Sonarr ? hung.Task : Task.FromResult(_radarr);

        var pending = _service.OverviewAsync(CancellationToken.None);
        _time.Advance(DownloadService.UnknownReadLimit - TimeSpan.FromSeconds(1));
        await Task.Delay(50);
        Assert.False(pending.IsCompleted);

        _time.Advance(TimeSpan.FromSeconds(1));
        var overview = await pending.WaitAsync(TimeSpan.FromSeconds(30));
        Assert.Empty(overview.Unknown);
        Assert.True(overview.Enabled);

        // La lettura non è stata cancellata: finisce in cache per il poll dopo, senza rileggere.
        var calls = _arr.UnknownQueueCalls.Count;
        hung.SetResult([Unknown(1)]);
        Assert.Equal(["D1", "R1"], (await Listed()).Select(u => u.DownloadId));
        Assert.Equal(calls, _arr.UnknownQueueCalls.Count);
    }

    [Fact]
    public async Task TheOverviewStartsTheReadsTogether()
    {
        var sonarr = new TaskCompletionSource<IReadOnlyList<ArrQueueItem?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var radarrAsked = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _arr.UnknownQueue = kind =>
        {
            if (kind == ArrKind.Sonarr)
            {
                return sonarr.Task;
            }

            radarrAsked.SetResult();
            return Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        };

        var pending = _service.OverviewAsync(CancellationToken.None);

        // In sequenza Radarr aspetterebbe la fine di Sonarr.
        await radarrAsked.Task.WaitAsync(TimeSpan.FromSeconds(30));
        sonarr.SetResult([]);
        Assert.Empty((await pending.WaitAsync(TimeSpan.FromSeconds(30))).Unknown);
    }

    [Fact]
    public async Task A404ThenAFailureIsNotOk()
    {
        _sonarr = [Unknown(1), Unknown(2)];
        _arr.RemoveFromQueue = (_, id, _) => Task.FromException(id == 1 ? new ArrException(ArrError.Unreachable, status: 404) : new ArrException(ArrError.Unreachable, status: 500));

        Assert.Equal(BlockedOutcome.Unavailable, await _service.RemoveUnknownAsync("Sonarr", "D1"));
    }

    [Fact]
    public async Task AFailureAfterTheTorrentIsGoneIsOk()
    {
        // Il primo elemento toglie il torrent: gli altri possono non esserci più.
        _sonarr = [Unknown(1), Unknown(2)];
        _arr.RemoveFromQueue = (_, id, _) => id == 1 ? Task.CompletedTask : Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        Assert.Equal(BlockedOutcome.Ok, await _service.RemoveUnknownAsync("Sonarr", "D1"));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task AnItemWithoutARealIdIsNeitherListedNorRemoved(int id)
    {
        _sonarr = [Unknown(id), Unknown(1)];

        Assert.Empty(await Listed());
        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Sonarr", "D1"));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task AnItemAlreadyGoneIsNotAFailure()
    {
        _sonarr = [Unknown(1)];
        _arr.RemoveFromQueue = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 404));

        Assert.Equal(BlockedOutcome.Ok, await _service.RemoveUnknownAsync("Sonarr", "D1"));
    }
}
