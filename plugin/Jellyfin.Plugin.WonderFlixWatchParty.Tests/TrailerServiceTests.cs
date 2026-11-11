using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class TrailerServiceTests : IDisposable
{
    private const string VideoId = "25WcssMq1VM";
    private static readonly Guid UserA = Guid.NewGuid();
    private static readonly Guid UserB = Guid.NewGuid();
    private static readonly TrailerSubject Movie = new(null, "movie", 7);

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "wf-trailer-service-" + Guid.NewGuid().ToString("N"));
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTrailerDownloader _downloader = new();
    private readonly TaskCompletionSource _gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TrailerCache _cache;
    private readonly TrailerService _service;

    public TrailerServiceTests()
    {
        _seerr.Movies[7] = new SeerrMovie
        {
            Id = 7,
            RelatedVideos = [new SeerrVideo { Site = "YouTube", Type = "Trailer", Url = "https://www.youtube.com/watch?v=" + VideoId }],
        };
        _cache = new TrailerCache(_folder, _time);
        var resolver = new TrailerResolver(new FakeTrailerLibrary(), _seerr, new FakeSeerrSettings(), _time);
        _service = new TrailerService(resolver, _downloader, _cache, _time, NullLogger<TrailerService>.Instance);
    }

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, true);
        }
    }

    [Fact]
    public async Task StartDownloadsOnceForTwoUsers()
    {
        _downloader.Gate = _gate.Task;

        var a = await _service.StartAsync(UserA, Movie, default);
        var b = await _service.StartAsync(UserB, Movie, default);

        Assert.Equal(TrailerStates.Downloading, a.State);
        Assert.Equal(TrailerStates.Downloading, b.State);
        Assert.Equal(VideoId, a.Key);
        Assert.Equal(VideoId, b.Key);

        _gate.SetResult();
        await _service.Pending(VideoId)!;

        Assert.Equal(1, _downloader.DownloadCalls);
        Assert.Equal(TrailerStates.Ready, _service.Status(VideoId)?.State);
    }

    [Fact]
    public async Task ReadyFileIsServedWithoutDownloading()
    {
        File.WriteAllBytes(_cache.PathFor(VideoId), [1]);

        var status = await _service.StartAsync(UserA, Movie, default);

        Assert.Equal(TrailerStates.Ready, status.State);
        Assert.Equal(0, _downloader.DownloadCalls);
    }

    [Theory]
    [InlineData(TrailerDownloadOutcome.Failed, false)]
    [InlineData(TrailerDownloadOutcome.Ok, true)]
    public async Task UnavailableAndFailedBecomeFailed(TrailerDownloadOutcome outcome, bool throws)
    {
        _downloader.Outcome = outcome;
        _downloader.Throw = throws;

        await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;

        Assert.Equal(TrailerStates.Failed, _service.Status(VideoId)?.State);

        _downloader.Throw = false;
        _downloader.Outcome = TrailerDownloadOutcome.Ok;
        var retry = await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;

        Assert.Equal(TrailerStates.Downloading, retry.State);
        Assert.Equal(2, _downloader.DownloadCalls);
        Assert.Equal(TrailerStates.Ready, _service.Status(VideoId)?.State);
    }

    [Fact]
    public async Task NoTrailerIsNone()
    {
        _seerr.Movies.Clear();

        var status = await _service.StartAsync(UserA, Movie, default);

        Assert.Equal(TrailerStates.None, status.State);
        Assert.Null(status.Key);
        Assert.False((await _service.InfoAsync(UserA, Movie, default)).Available);
    }

    [Fact]
    public async Task InfoSaysAvailableWithoutDownloading()
    {
        var info = await _service.InfoAsync(UserA, Movie, default);

        Assert.True(info.Available);
        Assert.Equal(0, _downloader.DownloadCalls);
    }

    [Fact]
    public void StatusOfAnUnknownKeyIsNull() => Assert.Null(_service.Status("neverSeenXXX"));

    [Fact]
    public async Task OpenStreamOnlyForReadyResolvedKeys()
    {
        // mai risolta, anche se il file c'è
        File.WriteAllBytes(_cache.PathFor("dQw4w9WgXcQ"), [1]);
        Assert.Null(_service.OpenStream("dQw4w9WgXcQ"));

        // risolta ma ancora in download
        _downloader.Gate = _gate.Task;
        await _service.StartAsync(UserA, Movie, default);
        Assert.Null(_service.OpenStream(VideoId));

        // pronta
        _gate.SetResult();
        await _service.Pending(VideoId)!;
        var stream = _service.OpenStream(VideoId);

        Assert.NotNull(stream);
        Assert.Equal(_cache.PathFor(VideoId), stream.Value.Path);
        stream.Value.Lease.Dispose();
    }

    private static string IdOf(int tmdbId) => "vid" + tmdbId.ToString("D8");

    [Fact]
    public async Task AtMostTwoDownloadsRunAtOnce()
    {
        var subjects = new[] { 21, 22, 23 }.Select(n => new TrailerSubject(null, "movie", n)).ToArray();
        foreach (var n in new[] { 21, 22, 23 })
        {
            _seerr.Movies[n] = new SeerrMovie
            {
                Id = n,
                RelatedVideos = [new SeerrVideo { Site = "YouTube", Type = "Trailer", Url = "https://www.youtube.com/watch?v=" + IdOf(n) }],
            };
            _downloader.Gates[IdOf(n)] = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        foreach (var subject in subjects)
        {
            var status = await _service.StartAsync(UserA, subject, default);
            Assert.Equal(TrailerStates.Downloading, status.State);
        }

        // Quali due prendono i posti non è detto (tre Task.Run): si sblocca uno di quelli partiti davvero.
        await WaitFor(() => _downloader.Started.Count == 2);
        await Task.Delay(100);
        Assert.Equal(2, _downloader.DownloadCalls);
        var started = _downloader.Started.ToArray();
        var waiting = subjects.Select(s => IdOf(s.TmdbId!.Value)).Single(id => !started.Contains(id));
        Assert.Equal(TrailerStates.Downloading, _service.Status(waiting)?.State); // aspetta, ma per chi chiede sta scaricando

        _downloader.Gates[started[0]].SetResult();
        await WaitFor(() => _downloader.Started.Count == 3);

        foreach (var id in new[] { started[1], waiting })
        {
            _downloader.Gates[id].SetResult();
        }

        foreach (var n in new[] { 21, 22, 23 })
        {
            await _service.Pending(IdOf(n))!;
        }

        Assert.Equal(2, _downloader.MaxRunning);
    }

    [Fact]
    public async Task StopCancelsTheRunningDownload()
    {
        _downloader.Gate = _gate.Task;
        await _service.StartAsync(UserA, Movie, default);
        await WaitFor(() => _downloader.DownloadCalls == 1);
        Assert.False(_downloader.LastToken.IsCancellationRequested);

        _service.Stop();

        Assert.True(_downloader.LastToken.IsCancellationRequested);
        _gate.SetResult();
        await _service.Pending(VideoId)!;
    }

    [Fact]
    public async Task UnavailableIsRememberedForADay()
    {
        _downloader.Outcome = TrailerDownloadOutcome.Unavailable;
        await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;
        Assert.Equal(TrailerStates.Failed, _service.Status(VideoId)?.State);

        var again = await _service.StartAsync(UserA, Movie, default);

        Assert.Equal(TrailerStates.Failed, again.State);
        Assert.Equal(1, _downloader.DownloadCalls);

        _time.Advance(TrailerService.UnavailableFor + TimeSpan.FromSeconds(1));
        var later = await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;

        Assert.Equal(TrailerStates.Downloading, later.State);
        Assert.Equal(2, _downloader.DownloadCalls);
    }

    [Fact]
    public async Task FailedIsNotRemembered()
    {
        _downloader.Outcome = TrailerDownloadOutcome.Failed;
        await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;

        var again = await _service.StartAsync(UserA, Movie, default);
        await _service.Pending(VideoId)!;

        Assert.Equal(TrailerStates.Downloading, again.State);
        Assert.Equal(2, _downloader.DownloadCalls);
    }

    private static async Task WaitFor(Func<bool> condition)
    {
        for (var i = 0; i < 200 && !condition(); i++)
        {
            await Task.Delay(10);
        }

        Assert.True(condition());
    }
}
