using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SubtitlesControllerTests
{
    private readonly FakeServer _server = new();
    private readonly FakeSubtitleTools _tools = new();
    private readonly SubtitleService _service;
    private readonly User _toad = new("toad", "provider", "reset");
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly Guid _video = Guid.NewGuid();

    public SubtitlesControllerTests()
    {
        _service = new SubtitleService(_tools, _server, _server, NullLogger<SubtitleService>.Instance);
        _server.Users[_toad.Id] = new UserRef(_toad.Id, _toad.Username, true, true, CanManageSubtitles: true);
        _server.Users[_mario.Id] = new UserRef(_mario.Id, _mario.Username, true, true);
        _tools.Videos.Add(_video);
    }

    private SubtitlesController Controller(User user) =>
        new(
            new FakeAuthorizationContext(new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true }),
            _service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    private string Id => _video.ToString("N");

    [Fact]
    public async Task SubtitleStatusesMapToCodes()
    {
        var dto = new RemoteSubtitleDto("open_1", "open", "Ciao", "ita", "srt", null, null, false, false, false, false);
        _tools.Results.Add(dto);
        var controller = Controller(_toad);

        var found = Assert.IsType<OkObjectResult>((await controller.Search(Id, "ita", null)).Result);
        Assert.Equal(dto, Assert.Single(Assert.IsAssignableFrom<IReadOnlyList<RemoteSubtitleDto>>(found.Value)));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await controller.Search(Id, "it", null)).Result!));
        Assert.Equal(StatusCodes.Status403Forbidden, Status((await Controller(_mario).Search(Id, "ita", null)).Result!));

        var download = new DownloadSubtitleRequest { SubtitleId = "open_1" };
        Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.Download(Id, download)));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await controller.Download(Id, new DownloadSubtitleRequest())));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_mario).Download(Id, download)));

        var upload = new UploadSubtitleRequest { Language = "ita", Format = "srt", Data = Convert.ToBase64String([1, 2, 3]) };
        Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.Upload(Id, upload)));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await controller.Upload(Id, new UploadSubtitleRequest())));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_mario).Upload(Id, upload)));

        _tools.Failure = new InvalidOperationException("provider giù");
        var failedDownload = Assert.IsType<ObjectResult>(await controller.Download(Id, download));
        Assert.Equal(StatusCodes.Status502BadGateway, failedDownload.StatusCode);
        Assert.Equal(new SubtitleErrorDto("DownloadFailed"), failedDownload.Value);
        var failedUpload = Assert.IsType<ObjectResult>(await controller.Upload(Id, upload));
        Assert.Equal(StatusCodes.Status502BadGateway, failedUpload.StatusCode);
        Assert.Equal(new SubtitleErrorDto("UploadFailed"), failedUpload.Value);
    }
}
