using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeServer _server = new();
    private readonly SpaceService _space;
    private readonly SpaceHostedService _hosted;

    public SpaceHostedServiceTests()
    {
        _space = new SpaceService(
            new FakeArrClient(),
            new FakeSeerrClient(),
            new FakeSeerrSettings(),
            new FakeQbitClient(),
            new FakeFileProbe(),
            new FakeLibraryRefresh(),
            new FakeSpaceSettings(),
            new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance),
            new FakeViewingFacts(),
            new FakeSeriesIndex(),
            TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time)),
            _server,
            TestDownloads.Create(new FakeArrClient(), _time, _folder.DownloadsFile),
            _time,
            NullLogger<SpaceService>.Instance);
        _hosted = new SpaceHostedService(_space, _time, NullLogger<SpaceHostedService>.Instance);
    }

    public void Dispose()
    {
        _hosted.Dispose();
        _folder.Dispose();
    }

    private static async Task<bool> Eventually(Func<bool> condition)
    {
        for (var i = 0; i < 100 && !condition(); i++)
        {
            await Task.Delay(50);
        }

        return condition();
    }

    [Fact]
    public async Task TheFirstScanRunsAfterTheDelay()
    {
        await _hosted.StartAsync(CancellationToken.None);

        await Task.Run(() => _time.Advance(SpaceHostedService.FirstScanDelay - TimeSpan.FromSeconds(1)));
        Assert.Null(_space.LastScan);

        await Task.Run(() => _time.Advance(TimeSpan.FromSeconds(1)));
        Assert.True(await Eventually(() => _space.LastScan is not null));
    }

    [Fact]
    public async Task QueuedOperationsRunWhileTheServiceLives()
    {
        _space.LastScan = new SpaceScan
        {
            Titles = new Dictionary<string, ScanTitle> { ["movie:12"] = new("Coco", 354912, "/srv/media", [], []) },
        };
        await _hosted.StartAsync(CancellationToken.None);

        var (_, id) = _space.Start(SpaceKinds.Movie, "movie:12");

        Assert.True(await Eventually(() => _space.Operation(id!)!.State is not SpaceOperationStates.Queued));
        await _hosted.StopAsync(CancellationToken.None);
    }
}
