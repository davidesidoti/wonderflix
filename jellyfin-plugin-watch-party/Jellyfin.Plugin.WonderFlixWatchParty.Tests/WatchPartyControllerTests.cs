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

public sealed class WatchPartyControllerTests : IDisposable
{
    private static readonly Guid Group = Guid.NewGuid();

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _user = new("mario", "provider", "reset");
    private readonly PartyHub _hub;
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;

    public WatchPartyControllerTests()
    {
        _hub = new PartyHub(
            _server, _server, _server, new PartyRegistry(), new ChatHistory(), new RateLimiter(_time), _time,
            NullLogger<PartyHub>.Instance);
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _server.Sessions.Add(new CallerSession("s-mario", _user.Id, "Mario"));
        _server.Groups[Group] = ["Mario"];
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private WatchPartyController Controller(string deviceId = "s-mario")
    {
        var auth = new AuthorizationInfo
        {
            DeviceId = deviceId,
            Client = "WonderFlix",
            User = _user,
            IsAuthenticated = true,
        };
        return new WatchPartyController(new FakeAuthorizationContext(auth), _server, _hub, _presence)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static EventRequest Chat(string text) => new() { Type = EventTypes.Chat, Text = text };

    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = Controller().GetInfo().Value!;
        Assert.Equal("1.1.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties" }, info.Features);
    }

    [Fact]
    public async Task UnknownCallerIs409()
    {
        var controller = Controller("altro-dispositivo");
        Assert.IsType<ConflictResult>((await controller.Join(Group)).Result);
        Assert.IsType<ConflictResult>((await controller.PostEvent(Group, Chat("x"), CancellationToken.None)).Result);
        Assert.IsType<NoContentResult>(await controller.Leave(Group));
    }

    [Fact]
    public async Task JoinOkAndForbidden()
    {
        var joined = await Controller().Join(Group);
        Assert.Empty(joined.Value!.Messages);
        var forbidden = await Controller().Join(Guid.NewGuid());
        Assert.Equal(StatusCodes.Status403Forbidden, Assert.IsType<StatusCodeResult>(forbidden.Result).StatusCode);
    }

    [Fact]
    public async Task EventsOkInvalidAndRateLimited()
    {
        var controller = Controller();
        var ok = await controller.PostEvent(Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal("Mario", ok.Value!.UserName);
        var invalid = await controller.PostEvent(Group, new EventRequest { Type = "Poll" }, CancellationToken.None);
        Assert.IsType<BadRequestResult>(invalid.Result);
        for (var i = 0; i < 4; i++)
        {
            await controller.PostEvent(Group, Chat("x"), CancellationToken.None);
        }

        var limited = await controller.PostEvent(Group, Chat("x"), CancellationToken.None);
        Assert.Equal(StatusCodes.Status429TooManyRequests, Assert.IsType<StatusCodeResult>(limited.Result).StatusCode);
    }

    [Fact]
    public async Task LeaveStopsForwarding()
    {
        var luigi = _server.AddSession("s-luigi", "Luigi");
        _server.Groups[Group].Add("Luigi");
        _hub.Join(luigi, Group);
        await Controller().Join(Group);
        Assert.IsType<NoContentResult>(await Controller().Leave(Group));
        await _hub.PostAsync(luigi, Group, Chat("ciao"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task JoiningOrLeavingTellsFriends()
    {
        var luigi = _server.AddUser("Luigi");
        _server.Users[_user.Id] = new UserRef(_user.Id, "Mario", true, true);
        _server.AddSession("s-luigi", luigi);
        await _friends.RequestAsync(_user.Id, luigi.Id);
        await _friends.AcceptAsync(luigi.Id, _user.Id);
        _server.Sent.Clear();

        await Controller().Join(Group);
        _time.Advance(PresenceTracker.Delay);
        Assert.Single(_server.SentTo("s-luigi"));

        await Controller().Leave(Group);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, _server.SentTo("s-luigi").Count);
    }
}
