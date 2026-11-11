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
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTrailerDownloader _downloader = new();
    private readonly TrailerService _service;
    private readonly TrailersHostedService _hosted;

    public TrailersHostedServiceTests()
    {
        _cache = new TrailerCache(_folder, _time);
        _seerr.Movies[7] = new Seerr.SeerrMovie
        {
            Id = 7,
            RelatedVideos = [new Seerr.SeerrVideo { Site = "YouTube", Type = "Trailer", Url = "https://www.youtube.com/watch?v=25WcssMq1VM" }],
        };
        var resolver = new TrailerResolver(new FakeTrailerLibrary(), _seerr, new FakeSeerrSettings(), _time);
        _service = new TrailerService(resolver, _downloader, _cache, _time, NullLogger<TrailerService>.Instance);
        _hosted = new TrailersHostedService(_cache, _service, _time, NullLogger<TrailersHostedService>.Instance);
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

    [Fact]
    public async Task StopCancelsTheRunningDownload()
    {
        var release = new TaskCompletionSource();
        _downloader.Gate = release.Task;
        await _hosted.StartAsync(CancellationToken.None);
        await _service.StartAsync(Guid.NewGuid(), new TrailerSubject(null, "movie", 7), default);
        for (var i = 0; i < 200 && _downloader.DownloadCalls == 0; i++)
        {
            await Task.Delay(10);
        }

        Assert.Equal(1, _downloader.DownloadCalls);
        Assert.False(_downloader.LastToken.IsCancellationRequested);

        await _hosted.StopAsync(CancellationToken.None);

        Assert.True(_downloader.LastToken.IsCancellationRequested);
        release.SetResult();
    }
}
