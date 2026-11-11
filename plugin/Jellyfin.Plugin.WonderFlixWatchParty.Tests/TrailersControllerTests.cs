using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class TrailersControllerTests : IDisposable
{
    private const string VideoId = "25WcssMq1VM";

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "wf-trailers-controller-" + Guid.NewGuid().ToString("N"));
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTrailerDownloader _downloader = new();
    private readonly TrailerService _service;
    private readonly TrailersController _controller;

    public TrailersControllerTests()
    {
        _seerr.Movies[7] = new SeerrMovie
        {
            Id = 7,
            RelatedVideos = [new SeerrVideo { Site = "YouTube", Type = "Trailer", Url = "https://www.youtube.com/watch?v=" + VideoId }],
        };
        var cache = new TrailerCache(_folder, _time);
        var resolver = new TrailerResolver(new FakeTrailerLibrary(), _seerr, new FakeSeerrSettings(), _time);
        _service = new TrailerService(resolver, _downloader, cache, NullLogger<TrailerService>.Instance);
        var user = new User("mario", "provider", "reset");
        _controller = new TrailersController(
            new FakeAuthorizationContext(new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true }),
            _service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, true);
        }
    }

    [Fact]
    public async Task InfoNeedsASubject()
    {
        Assert.IsType<BadRequestResult>((await _controller.Info(null, null, null)).Result);
        Assert.IsType<BadRequestResult>((await _controller.Info(null, null, "movie")).Result);
        Assert.IsType<BadRequestResult>((await _controller.Info("not-a-guid", null, null)).Result);
    }

    [Fact]
    public async Task InfoRejectsAnUnknownType()
    {
        Assert.IsType<BadRequestResult>((await _controller.Info(null, 7, "person")).Result);
        Assert.IsType<BadRequestResult>((await _controller.Info(null, 7, null)).Result);
    }

    [Fact]
    public async Task InfoSaysIfThereIsATrailer()
    {
        var result = await _controller.Info(null, 7, "movie");
        Assert.True(result.Value!.Available);
        Assert.False((await _controller.Info(null, 8, "movie")).Value!.Available);
    }

    [Fact]
    public async Task StartReturnsTheJobState()
    {
        var result = await _controller.Start(new TrailerSubjectRequest { TmdbId = 7, Type = "movie" });
        Assert.Equal(VideoId, result.Value!.Key);
        Assert.Contains(result.Value.State, new[] { TrailerStates.Downloading, TrailerStates.Ready });
        Assert.IsType<BadRequestResult>((await _controller.Start(new TrailerSubjectRequest())).Result);
        Assert.IsType<BadRequestResult>((await _controller.Start(null)).Result);
        await _service.Pending(VideoId)!;
    }

    [Fact]
    public async Task StatusOfAnUnknownKeyIs404()
    {
        Assert.IsType<NotFoundResult>(_controller.Status("nope").Result);
        Assert.IsType<NotFoundResult>(_controller.Status(null).Result);

        await _controller.Start(new TrailerSubjectRequest { TmdbId = 7, Type = "movie" });
        await _service.Pending(VideoId)!;
        Assert.Equal(TrailerStates.Ready, _controller.Status(VideoId).Value!.State);
    }

    [Fact]
    public void StreamOfAnUnresolvedKeyIs404() => Assert.IsType<NotFoundResult>(_controller.Stream("nope"));

    [Fact]
    public async Task StreamServesMp4WithRanges()
    {
        await _controller.Start(new TrailerSubjectRequest { TmdbId = 7, Type = "movie" });
        await _service.Pending(VideoId)!;

        var file = Assert.IsType<PhysicalFileResult>(_controller.Stream(VideoId));

        Assert.True(file.EnableRangeProcessing);
        Assert.Equal("video/mp4", file.ContentType);
        Assert.EndsWith(VideoId + ".mp4", file.FileName);
    }
}
