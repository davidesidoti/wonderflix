using System.Reflection;
using System.Text.Json;
using Jellyfin.Extensions.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadsControllerTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;
    private readonly DownloadsController _controller;

    public DownloadsControllerTests()
    {
        // Animals (106 minuti): due WEB 1080p buoni.
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([Movie(12, title: "Animals", year: 2025, runtime: 106)]);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(
            [Release("a", WebDl1080, "WEBDL-1080p", 2.9, 150), Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3)]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4)]);
        _service = TestDownloads.Create(_arr, _time, _folder.DownloadsFile);
        _controller = new DownloadsController(_service) { ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() } };
    }

    public void Dispose() => _folder.Dispose();

    private static int Status(IActionResult? result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result?.GetType().Name),
    };

    private static string Reason(IActionResult result) => ((DownloadsErrorDto)((ObjectResult)result).Value!).Reason;

    private static GrabRequest Body(string? key = "movie:12", string? guid = "b", int indexerId = 3) =>
        new() { Key = key, Guid = guid, IndexerId = indexerId };

    [Fact]
    public void TheClassRequiresElevation()
    {
        var authorize = Assert.Single(typeof(DownloadsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, authorize.Policy);
    }

    [Fact]
    public async Task AGrabIsNoContentAndSearchNowAcceptedOnceTheTitleIsFollowed()
    {
        Assert.Equal(StatusCodes.Status400BadRequest, Status(_controller.SearchNow(new KeyRequest { Key = "movie:12" })));

        Assert.Equal(StatusCodes.Status204NoContent, Status(await _controller.Grab(Body())));

        Assert.Equal(StatusCodes.Status202Accepted, Status(_controller.SearchNow(new KeyRequest { Key = "movie:12" })));
        Assert.Equal(StatusCodes.Status204NoContent, Status(_controller.Accept(new KeyRequest { Key = "movie:12" })));
    }

    [Fact]
    public async Task ExpiredIsConflict()
    {
        var result = await _controller.Grab(Body(guid: "gone"));

        Assert.Equal(StatusCodes.Status409Conflict, Status(result));
        Assert.Equal("Expired", Reason(result));
    }

    [Fact]
    public async Task UnavailableIsServiceUnavailable()
    {
        _arr.Releases = (_, _) => Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable));

        var result = await _controller.Grab(Body());

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(result));
        Assert.Equal("Unavailable", Reason(result));
    }

    [Fact]
    public async Task RefusedIsBadGateway()
    {
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        var result = await _controller.Grab(Body());

        Assert.Equal(StatusCodes.Status502BadGateway, Status(result));
        Assert.Equal("Refused", Reason(result));
    }

    [Fact]
    public async Task ASecondGrabOfTheSameTitleIsBusy()
    {
        var gate = new TaskCompletionSource<IReadOnlyList<ArrRelease?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _arr.Releases = (_, _) => gate.Task;
        var first = _controller.Grab(Body());

        var second = await _controller.Grab(Body());

        Assert.Equal(StatusCodes.Status409Conflict, Status(second));
        Assert.Equal("Busy", Reason(second));
        gate.SetResult([Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3)]);
        Assert.Equal(StatusCodes.Status204NoContent, Status(await first));
    }

    [Fact]
    public async Task ABadKeyIsBadRequest()
    {
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await _controller.Search("nope")).Result));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await _controller.Search(null)).Result));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await _controller.Grab(Body(key: "nope"))));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await _controller.Grab(null)));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await _controller.Grab(Body(key: null))));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await _controller.Grab(Body(guid: " "))));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(_controller.Accept(new KeyRequest { Key = "nope" })));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(_controller.Accept(null)));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(_controller.SearchNow(new KeyRequest())));
    }

    [Fact]
    public async Task AGrabWithoutAnIndexerIsBadRequestNotConflict()
    {
        var body = JsonSerializer.Deserialize<GrabRequest>("""{"Key":"movie:12","Guid":"b"}""");

        Assert.Equal(StatusCodes.Status400BadRequest, Status(await _controller.Grab(body)));
        Assert.Empty(_arr.GrabCalls);
    }

    [Fact]
    public async Task TheOverviewReportsAServiceError()
    {
        _arr.Queue = kind => kind == ArrKind.Radarr
            ? Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unauthorized))
            : Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        await _service.RunCycleAsync(CancellationToken.None);

        var overview = _controller.Overview().Value!;

        Assert.Equal("Unauthorized", overview.RadarrError);
        Assert.Null(overview.SonarrError);
    }

    [Fact]
    public async Task NullFieldsAreWrittenAsNull()
    {
        var search = (await _controller.Search("movie:12")).Value!;

        // Come Jellyfin: le sue opzioni omettono i null, quindi ogni campo nullable ha JsonIgnoreCondition.Never.
        var json = JsonSerializer.Serialize(search, JsonDefaults.PascalCaseOptions);

        Assert.Contains("\"Error\":null", json);
        Assert.Contains("\"Current\":null", json);
        var overview = JsonSerializer.Serialize(_controller.Overview().Value, JsonDefaults.PascalCaseOptions);
        Assert.Contains("\"SonarrError\":null", overview);
        Assert.Contains("\"RadarrError\":null", overview);
        Assert.Contains("\"ReviewAt\":null", overview);
    }

    [Fact]
    public void EveryNullablePropertyOfTheDtosIsWrittenWhenNull()
    {
        var release = new DownloadReleaseDto("g", 1, "idx", "t", "WEBRip-1080p", 1080, 1, 1, null);
        var dtos = new object[]
        {
            release,
            new DownloadChoiceDto("movie:1", "Movie", "T", null, T0, release, null, null, false),
            new DownloadItemDto("movie:1", "Movie", "T", null, "Waiting", null, T0, null, null),
            new ReviewItemDto("movie:1", "Movie", "T", null, 1, 1, "q"),
            new DownloadRejectedDto(release, "Arr", null),
            new DownloadProfileDto("Radarr", 4, "Main", 50, null),
        };

        foreach (var dto in dtos)
        {
            var json = JsonSerializer.Serialize(dto, dto.GetType(), JsonDefaults.PascalCaseOptions);
            foreach (var property in dto.GetType().GetProperties().Where(p => Nullable.GetUnderlyingType(p.PropertyType) is not null || (!p.PropertyType.IsValueType && p.GetValue(dto) is null)))
            {
                Assert.Contains($"\"{property.Name}\":null", json);
            }
        }
    }

    [Fact]
    public async Task ProfilesCarryTheirThresholds()
    {
        var profiles = (await _controller.Profiles()).Value!;

        Assert.Equal(["Radarr", "Sonarr"], profiles.Select(p => p.Service));
        Assert.All(profiles, p => Assert.Equal((4, "Main", 50, 150), (p.ProfileId, p.Name, p.MinScore, p.TargetScore)));
    }

    [Fact]
    public async Task ProfilesWithEveryServiceDownAreUnavailable()
    {
        _arr.QualityProfiles = _ => Task.FromException<IReadOnlyList<ArrQualityProfile?>>(new ArrException(ArrError.Unreachable));

        var result = (await _controller.Profiles()).Result!;

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(result));
        Assert.Equal("Unavailable", Reason(result));
    }
}
