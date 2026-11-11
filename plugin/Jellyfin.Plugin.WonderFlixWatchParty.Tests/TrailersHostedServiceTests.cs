using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class TrailersHostedServiceTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "wf-trailers-hosted-" + Guid.NewGuid().ToString("N"));
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));
    private readonly TrailerCache _cache;
    private readonly TrailersHostedService _hosted;

    public TrailersHostedServiceTests()
    {
        _cache = new TrailerCache(_folder, _time);
        _hosted = new TrailersHostedService(_cache, _time, NullLogger<TrailersHostedService>.Instance);
    }

    public void Dispose()
    {
        _hosted.Dispose();
        Directory.Delete(_folder, true);
    }

    [Fact]
    public async Task StartClearsTheCache()
    {
        File.WriteAllBytes(_cache.PathFor("old"), [1]);

        await _hosted.StartAsync(CancellationToken.None);

        Assert.False(File.Exists(_cache.PathFor("old")));
    }

    [Fact]
    public async Task SweepRunsEveryFiveMinutes()
    {
        await _hosted.StartAsync(CancellationToken.None);
        File.WriteAllBytes(_cache.PathFor("a"), [1]);
        _cache.Touch("a");

        // I tick a 5, 10 ... 60 minuti trovano il file ancora giovane (non visto da più di un'ora si toglie).
        await Task.Run(() => _time.Advance(TrailerCache.KeepFor));
        Assert.True(File.Exists(_cache.PathFor("a")));

        // Fino a 64:59 l'ultimo tick è quello dei 60 minuti; il successivo, a 65, lo toglie.
        await Task.Run(() => _time.Advance(TrailersHostedService.SweepInterval - TimeSpan.FromSeconds(1)));
        Assert.True(File.Exists(_cache.PathFor("a")));

        await Task.Run(() => _time.Advance(TimeSpan.FromSeconds(1)));
        Assert.False(File.Exists(_cache.PathFor("a")));
    }
}
