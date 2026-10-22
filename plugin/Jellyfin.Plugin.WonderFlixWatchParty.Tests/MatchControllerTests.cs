using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;
    private readonly PartyDirectory _parties;
    private readonly MatchService _match;

    public MatchControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        _server.AddSession("s-mario", _server.Users[_mario.Id]);
        _server.AddSession("s-luigi", _server.Users[_luigi.Id]);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _parties = new PartyDirectory(_time);
        _match = TestMatch.Create(_server, _folder, _time, _friends, _parties);
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    private MatchController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new MatchController(new FakeAuthorizationContext(auth), _match)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static MatchStateDto State(ActionResult<MatchStateDto> result) =>
        Assert.IsType<MatchStateDto>(Assert.IsType<OkObjectResult>(result.Result).Value);

    private static void AssertReason(string reason, IActionResult? result, string? roomId = null)
    {
        var conflict = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal(new MatchErrorDto(reason, roomId), conflict.Value);
    }

    [Fact]
    public async Task TheWholeMatchGoesThroughTheEndpoints()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var dune = Guid.NewGuid();
        _server.MatchCandidates.Add(new MatchCandidate(dune, true, null));

        var room = State(await Controller(_mario).Open()).RoomId;
        Assert.IsType<NoContentResult>(await Controller(_mario).Invite(room, new InviteRequest { UserIds = [_luigi.Id.ToString("N")] }));
        Assert.Equal(2, State(await Controller(_luigi).Join(room)).Members.Count);

        var started = State(await Controller(_mario).Start(room, new MatchStartRequest { Type = "movies", Duration = "any" }));
        Assert.Equal(new[] { dune.ToString("N") }, started.Stack);

        var yes = new MatchVoteRequest { ItemId = dune.ToString("N"), Yes = true };
        Assert.IsType<NoContentResult>(await Controller(_mario).Vote(room, yes));
        Assert.IsType<NoContentResult>(await Controller(_luigi).Vote(room, yes));
        Assert.Equal(new[] { dune.ToString("N") }, State(await Controller(_luigi).Get(room)).Matches);
        Assert.Single(State(await Controller(_mario).More(room)).Stack);

        var group = Guid.NewGuid();
        _parties.Register(group, _mario.Id, PartyModes.Private);
        Assert.IsType<NoContentResult>(await Controller(_mario).Party(room, new MatchPartyRequest { GroupId = group.ToString("N") }));
        Assert.Equal(group.ToString("N"), State(await Controller(_luigi).Get(room)).PartyGroupId);
        Assert.IsType<NoContentResult>(await Controller(_luigi).Leave(room));
    }

    [Fact]
    public async Task ConflictsCarryTheReason()
    {
        var room = State(await Controller(_mario).Open()).RoomId;
        var someone = Guid.NewGuid().ToString("N");

        AssertReason(MatchReasons.InAnotherRoom, (await Controller(_mario).Open()).Result, room);
        AssertReason(MatchReasons.NotMember, (await Controller(_luigi).Get(room)).Result);
        AssertReason(MatchReasons.NotInvited, (await Controller(_luigi).Join(room)).Result);
        AssertReason(MatchReasons.NotEnoughMembers, (await Controller(_mario).Start(room, new MatchStartRequest())).Result);
        AssertReason(MatchReasons.NotStarted, await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = someone, Yes = false }));
        AssertReason(MatchReasons.NotStarted, (await Controller(_mario).More(room)).Result);
        AssertReason(MatchReasons.NotCreator, await Controller(_luigi).Invite(room, new InviteRequest()));
        AssertReason(MatchReasons.Closed, await Controller(_mario).Party(someone, new MatchPartyRequest { GroupId = someone }));
    }

    [Fact]
    public async Task BadIdsAndBodiesAre400AndNever404()
    {
        var room = State(await Controller(_mario).Open()).RoomId;

        Assert.IsType<BadRequestResult>((await Controller(_mario).Get("non-un-id")).Result);
        Assert.IsType<BadRequestResult>((await Controller(_mario).Join("non-un-id")).Result);
        Assert.IsType<BadRequestResult>((await Controller(_mario).More("non-un-id")).Result);
        Assert.IsType<BadRequestResult>(await Controller(_mario).Leave("non-un-id"));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Invite("non-un-id", new InviteRequest()));
        Assert.IsType<BadRequestResult>((await Controller(_mario).Start(room, new MatchStartRequest { Type = "films" })).Result);
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = "x", Yes = true }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = Guid.NewGuid().ToString("N") }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, null));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Party(room, new MatchPartyRequest { GroupId = "x" }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Party(room, null));

        // Una sala sconosciuta: uscire va sempre bene.
        Assert.IsType<NoContentResult>(await Controller(_mario).Leave(Guid.NewGuid().ToString("N")));
    }

    [Fact]
    public async Task VotesBeyondTheLimitAre429()
    {
        var room = State(await Controller(_mario).Open()).RoomId;
        var vote = new MatchVoteRequest { ItemId = Guid.NewGuid().ToString("N"), Yes = true };
        for (var i = 0; i < 4; i++)
        {
            AssertReason(MatchReasons.NotStarted, await Controller(_mario).Vote(room, vote));
        }

        var limited = Assert.IsType<StatusCodeResult>(await Controller(_mario).Vote(room, vote));
        Assert.Equal(StatusCodes.Status429TooManyRequests, limited.StatusCode);
    }
}
