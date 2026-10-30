using System.Reflection;
using System.Text.Json;
using Jellyfin.Extensions.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeServer _server = new();
    private readonly SpaceService _service;
    private readonly SpaceController _controller;

    public SpaceControllerTests()
    {
        _service = new SpaceService(
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
            _time,
            NullLogger<SpaceService>.Instance);
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", IsAuthenticated = true };
        _controller = new SpaceController(_service, new FakeAuthorizationContext(auth))
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    public void Dispose() => _folder.Dispose();

    private static int Status(IActionResult? result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result?.GetType().Name),
    };

    private static string Reason(IActionResult result) => ((SpaceErrorDto)((ObjectResult)result).Value!).Reason;

    private static StartOperationRequest Body(string kind = "Movie", string key = "movie:12") => new() { Kind = kind, Key = key };

    private void WithScan(params string[] movieKeys) => _service.LastScan = new SpaceScan
    {
        Titles = movieKeys.ToDictionary(k => k, k => new ScanTitle("Coco", 354912, "/srv/media", [], [])),
    };

    [Fact]
    public void TheClassRequiresElevation()
    {
        var authorize = Assert.Single(typeof(SpaceController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, authorize.Policy);
    }

    [Fact]
    public async Task TheOverviewWorksWithoutAUser()
    {
        var overview = (await _controller.Overview()).Value!;

        Assert.Empty(overview.TopGenres);
        Assert.Empty(overview.Delete);
    }

    [Fact]
    public async Task RecalculateAnswers202AndStartsTheScan()
    {
        Assert.Equal(202, Status(_controller.Recalculate()));
        for (var i = 0; i < 100 && _service.LastScan is null; i++)
        {
            await Task.Delay(50);
        }

        Assert.NotNull(_service.LastScan);
    }

    [Fact]
    public void StartReturnsTheId()
    {
        WithScan("movie:12");

        var result = (_controller.Start(Body())).Result!;

        Assert.Equal(202, Status(result));
        Assert.False(string.IsNullOrEmpty(Assert.IsType<SpaceStartedDto>(((ObjectResult)result).Value).Id));
    }

    [Fact]
    public void StartMapsTheOutcomes()
    {
        Assert.Equal(("NotReady", 409), (Reason((_controller.Start(Body())).Result!), Status((_controller.Start(Body())).Result)));

        WithScan("movie:12");
        Assert.Equal(404, Status((_controller.Start(Body(key: "movie:99"))).Result));
        Assert.Equal("Unknown", Reason((_controller.Start(Body(key: "movie:99"))).Result!));
        Assert.Equal(400, Status((_controller.Start(Body(key: "series:12"))).Result));
        Assert.Equal(400, Status((_controller.Start(null)).Result));
        Assert.Equal(400, Status((_controller.Start(Body(kind: ""))).Result));

        Assert.Equal(202, Status((_controller.Start(Body())).Result));
        var busy = (_controller.Start(Body())).Result!;
        Assert.Equal((409, "Busy"), (Status(busy), Reason(busy)));
    }

    [Fact]
    public void TheOperationIsReadable()
    {
        WithScan("movie:12");
        var id = ((SpaceStartedDto)((ObjectResult)(_controller.Start(Body())).Result!).Value!).Id;

        var operation = _controller.Operation(id).Value!;

        Assert.Equal(("Movie", "movie:12"), (operation.Kind, operation.Key));
        Assert.NotEmpty(operation.Steps);
        Assert.Equal(404, Status(_controller.Operation("nope").Result));
    }

    [Fact]
    public void KeepAndUnkeep()
    {
        Assert.Equal(204, Status(_controller.Keep(new KeepRequest { Key = "movie:12", Title = "Coco" })));
        Assert.Equal("movie:12", Assert.Single(_service.Read(b => b.Kept)).Key);
        Assert.Equal(204, Status(_controller.Unkeep("movie:12")));
        Assert.Empty(_service.Read(b => b.Kept));

        Assert.Equal(400, Status(_controller.Keep(new KeepRequest { Key = "file:x", Title = "x" })));
        Assert.Equal(400, Status(_controller.Keep(null)));
        Assert.Equal(400, Status(_controller.Unkeep(null)));
    }

    [Fact]
    public async Task AKeptSeasonDisappearsFromTheOverview()
    {
        var row = new SpaceCandidateDto(
            "season:5:2", "Season", "Serie - Stagione 2", null, 2, "series:5", null, null, 1, 1, 0, null, 0, [], [], [], [], null, 0, null, null, []);
        _service.LastScan = new SpaceScan { Delete = [new ScanRow<SpaceCandidateDto>(row, ["season:5:2", "series:5"], [])] };
        Assert.Single((await _controller.Overview()).Value!.Delete);

        Assert.Equal(204, Status(_controller.Keep(new KeepRequest { Key = "season:5:2", Title = "Serie - Stagione 2" })));

        Assert.Empty((await _controller.Overview()).Value!.Delete);
        Assert.Equal("season:5:2", Assert.Single((await _controller.Overview()).Value!.Kept).Key);
    }

    [Fact]
    public void DroppingAPendingTorrentAnswers204Or404()
    {
        Assert.Equal(404, Status(_controller.DropPending("abc")));
    }

    [Fact]
    public void NullFieldsAreWritten()
    {
        var candidate = new SpaceCandidateDto(
            "movie:12", "Movie", "Coco", null, null, null, null, null, 1, 1, 0, null, 0, [], [], [], [], null, 0, null, null, []);

        var json = JsonSerializer.Serialize(candidate, JsonDefaults.PascalCaseOptions);

        Assert.Contains("\"Year\":null", json);
        Assert.Contains("\"FreeLaterAt\":null", json);
    }

    [Fact]
    public void TheBodiesReadTheirFields()
    {
        var start = JsonSerializer.Deserialize<StartOperationRequest>("""{"Kind":"Movie","Key":"movie:12"}""");
        Assert.Equal(("Movie", "movie:12"), (start!.Kind, start.Key));
        var keep = JsonSerializer.Deserialize<KeepRequest>("""{"Key":"movie:12","Title":"Coco"}""");
        Assert.Equal(("movie:12", "Coco"), (keep!.Key, keep.Title));
    }
}
