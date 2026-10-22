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

public sealed class PartiesControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _peach = new("peach", "provider", "reset");
    private readonly Guid _group = Guid.NewGuid();
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly PartyAnnouncer _announcer;
    private readonly PartyService _parties;

    public PartiesControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_peach.Id] = new UserRef(_peach.Id, "Peach", true, true);
        _server.Sessions.Add(new CallerSession("s-mario", _mario.Id, "Mario"));
        _server.Sessions.Add(new CallerSession("s-peach", _peach.Id, "Peach"));
        _server.Groups[_group] = ["Mario"];
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        var directory = new PartyDirectory(_time);
        _announcer = new PartyAnnouncer(
            directory, _server, _server, _friends, _server, _time, NullLogger<PartyAnnouncer>.Instance);
        _parties = new PartyService(
            directory, _server, _server, _server, _friends, new PartyRegistry(), _announcer, _server,
            new RateLimiter(_time), TestInbox.Create(_server, _folder, _time), NullLogger<PartyService>.Instance);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _announcer.Dispose();
        _folder.Dispose();
    }

    private PartiesController Controller(User user, string deviceId)
    {
        var auth = new AuthorizationInfo { DeviceId = deviceId, Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new PartiesController(new FakeAuthorizationContext(auth), _server, _parties, _presence)
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
    public async Task RegisterListDetailsAndCode()
    {
        var mario = Controller(_mario, "s-mario");
        var peach = Controller(_peach, "s-peach");

        var registered = await mario.Register(_group, new RegisterPartyRequest { Mode = PartyModes.Private });
        var code = registered.Value!.Code!;
        Assert.Equal(StatusCodes.Status409Conflict, Status((await mario.Register(_group, new RegisterPartyRequest { Mode = "Private" })).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await mario.Register(Guid.NewGuid(), new RegisterPartyRequest { Mode = "x" })).Result!));

        var details = await mario.Details(_group);
        Assert.Equal(code, details.Value!.Code);
        Assert.Equal(StatusCodes.Status403Forbidden, Status((await peach.Details(_group)).Result!));

        Assert.Empty(Assert.IsAssignableFrom<IReadOnlyList<PartySummary>>(
            Assert.IsType<OkObjectResult>((await peach.List()).Result).Value));
        var joined = await peach.JoinByCode(new JoinByCodeRequest { Code = code });
        Assert.Equal(_group.ToString("N"), joined.Value!.GroupId);
        Assert.Single(Assert.IsAssignableFrom<IReadOnlyList<PartySummary>>(
            Assert.IsType<OkObjectResult>((await peach.List()).Result).Value));
        Assert.Equal(StatusCodes.Status403Forbidden, Status((await peach.JoinByCode(new JoinByCodeRequest { Code = "ZZZZZZ" })).Result!));
    }

    [Fact]
    public async Task RegistrationTellsFriendsToRefresh()
    {
        await _friends.RequestAsync(_peach.Id, _mario.Id);
        await _friends.AcceptAsync(_mario.Id, _peach.Id);
        _server.Sent.Clear();

        await Controller(_mario, "s-mario").Register(_group, new RegisterPartyRequest { Mode = PartyModes.Private });
        _time.Advance(PresenceTracker.Delay);

        var payload = Assert.Single(_server.SentTo("s-peach"));
        Assert.Contains("FriendsChanged", payload);
    }

    [Fact]
    public async Task InvitesAndUnknownSessions()
    {
        var mario = Controller(_mario, "s-mario");
        await mario.Register(_group, new RegisterPartyRequest { Mode = PartyModes.Public });
        Assert.IsType<NoContentResult>(await mario.Invite(_group, new InviteRequest { UserIds = [] }));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_peach, "s-peach").Invite(_group, new InviteRequest())));

        // Senza la sessione di chi chiama: 409, come il canale.
        var stranger = Controller(_mario, "altro-dispositivo");
        Assert.IsType<ConflictResult>((await stranger.List()).Result);
        Assert.IsType<ConflictResult>((await stranger.Register(_group, new RegisterPartyRequest { Mode = "Public" })).Result);
    }
}
