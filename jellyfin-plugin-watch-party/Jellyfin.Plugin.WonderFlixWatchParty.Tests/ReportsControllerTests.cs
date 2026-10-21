using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ReportsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 21, 20, 0, 0, TimeSpan.Zero));
    private readonly ReportService _reports;
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly ReportedItem _movie;

    public ReportsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, _mario.Username, true, true);
        _reports = TestReports.Create(_server, _folder, _time, TestInbox.Create(_server, _folder, _time));
        _movie = _server.AddMovie("Dune");
    }

    public void Dispose() => _folder.Dispose();

    private ReportsController Controller() =>
        new(
            new FakeAuthorizationContext(new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true }),
            _reports)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    private static string N(Guid id) => id.ToString("N");

    private CreateReportRequest Request(Guid? itemId = null) =>
        new() { ItemId = N(itemId ?? _movie.Id), Type = ReportTypes.Other };

    [Fact]
    public void TheAdminEndpointsNeedElevation()
    {
        foreach (var type in new[] { typeof(ReportsController), typeof(SubtitlesController) })
        {
            Assert.Null(Assert.Single(type.GetCustomAttributes<AuthorizeAttribute>()).Policy);
        }

        string? Policy(string name) => typeof(ReportsController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>().SingleOrDefault()?.Policy;
        Assert.Equal(Policies.RequiresElevation, Policy(nameof(ReportsController.List)));
        Assert.Equal(Policies.RequiresElevation, Policy(nameof(ReportsController.Resolve)));
        Assert.Null(Policy(nameof(ReportsController.Create)));
        Assert.Null(Policy(nameof(ReportsController.Mine)));
    }

    [Fact]
    public async Task CreateMapsTheOutcomes()
    {
        var controller = Controller();
        var ok = await controller.Create(Request());
        Assert.IsType<ReportDto>(Assert.IsType<OkObjectResult>(ok.Result).Value);
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await controller.Create(new CreateReportRequest())).Result!));

        for (var i = 0; i < ReportService.MaxOpenPerUser - 1; i++)
        {
            Assert.Equal(StatusCodes.Status200OK, Status((await controller.Create(Request(_server.AddMovie($"Film {i}").Id))).Result!));
        }

        var conflict = Assert.IsType<ObjectResult>((await controller.Create(Request(_server.AddMovie("Ultimo").Id))).Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal(new ReportErrorDto("LimitReached"), conflict.Value);
    }

    [Fact]
    public async Task MineAndListReturnTheReports()
    {
        var controller = Controller();
        await controller.Create(Request());
        Assert.Single(Assert.IsType<ReportListDto>(Assert.IsType<OkObjectResult>((await controller.Mine(N(_movie.Id))).Result).Value).Items);
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await controller.Mine("abc")).Result!));
        Assert.Single(controller.List().Value!.Items);
    }

    [Fact]
    public async Task ResolveMapsTheOutcomes()
    {
        var controller = Controller();
        var id = ((ReportDto)((OkObjectResult)(await controller.Create(Request())).Result!).Value!).Id;
        var body = new ResolveReportRequest { Outcome = ReportOutcomes.Fixed };

        Assert.Equal(StatusCodes.Status400BadRequest, Status(await controller.Resolve("abc", body)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.Resolve(id, body)));
        var closed = Assert.IsType<ObjectResult>(await controller.Resolve(id, body));
        Assert.Equal(StatusCodes.Status409Conflict, closed.StatusCode);
        Assert.Equal(new ReportErrorDto("Closed"), closed.Value);
    }
}
