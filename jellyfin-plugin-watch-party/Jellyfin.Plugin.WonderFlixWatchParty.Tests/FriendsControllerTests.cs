using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class FriendsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;

    public FriendsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true);
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private FriendsController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new FriendsController(new FakeAuthorizationContext(auth), _friends)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    [Fact]
    public async Task RequestAcceptAndList()
    {
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).SendRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status409Conflict, Status(await Controller(_mario).SendRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).AcceptRequest(_mario.Id)));

        var friends = (await Controller(_mario).GetFriends()).Value!;
        Assert.Equal("Luigi", Assert.Single(friends.Friends).Name);
    }

    [Fact]
    public async Task MissingRequestIsForbiddenAndCancelOrRemoveAreNoContent()
    {
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_luigi).AcceptRequest(_mario.Id)));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_luigi).DeclineRequest(_mario.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).CancelRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).RemoveFriend(_luigi.Id)));
    }

    [Fact]
    public async Task SearchReturnsResultsAndRateLimits()
    {
        var found = await Controller(_mario).Search("lui");
        var results = Assert.IsAssignableFrom<IReadOnlyList<UserSearchResult>>(Assert.IsType<OkObjectResult>(found.Result).Value);
        Assert.Equal("Luigi", Assert.Single(results).Name);

        for (var i = 1; i < 30; i++)
        {
            await Controller(_mario).Search("lui");
        }

        Assert.Equal(StatusCodes.Status429TooManyRequests, Status((await Controller(_mario).Search("lui")).Result!));
    }
}
