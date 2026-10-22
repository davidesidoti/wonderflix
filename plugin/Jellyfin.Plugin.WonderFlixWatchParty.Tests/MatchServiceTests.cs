using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchServiceTests : IDisposable
{
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PartyDirectory _parties;
    private readonly MatchService _match;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;

    public MatchServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _server.AddSession("s-peach", _peach);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _parties = new PartyDirectory(_time);
        _match = TestMatch.Create(_server, _folder, _time, _friends, _parties);
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    private async Task<Guid> RoomWithLuigiAsync()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        Assert.Equal(HubStatus.Ok, (await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id)])).Status);
        Assert.Equal(HubStatus.Ok, _match.Join(_luigi.Id, room).Status);
        return room;
    }

    private static string Id(Guid id) => id.ToString("N");

    private IReadOnlyList<MatchStateDto> Updates(string sessionId) =>
        _server.SentTo(sessionId)
            .Select(payload => JsonSerializer.Deserialize<JsonElement>(payload))
            .Where(json => json.GetProperty("Type").GetString() == SocialEventTypes.MatchUpdated)
            .Select(json => json.GetProperty("State").Deserialize<MatchStateDto>()!)
            .ToList();

    private static void AssertConflict(string reason, MatchOutcome outcome, string? roomId = null)
    {
        Assert.Equal(HubStatus.Conflict, outcome.Status);
        Assert.Equal(reason, outcome.Reason);
        Assert.Equal(roomId, outcome.RoomId);
    }

    [Fact]
    public void OpeningGivesAWaitingRoomWithTheCreator()
    {
        var outcome = _match.Open(_mario.Id);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Equal(MatchPhases.Waiting, outcome.State!.Phase);
        Assert.Equal("Mario", outcome.State.CreatorName);
        Assert.Equal(Id(_mario.Id), Assert.Single(outcome.State.Members).UserId);
    }

    [Fact]
    public void OneOpenRoomPerUser()
    {
        var first = _match.Open(_mario.Id).State!.RoomId;
        AssertConflict(MatchReasons.InAnotherRoom, _match.Open(_mario.Id), first);
    }

    [Fact]
    public async Task OnlyMembersReadTheRoom()
    {
        var room = await RoomWithLuigiAsync();

        Assert.Equal(2, _match.Get(_luigi.Id, room).State!.Members.Count);
        AssertConflict(MatchReasons.NotMember, _match.Get(_peach.Id, room));
        AssertConflict(MatchReasons.NotMember, _match.Get(_mario.Id, Guid.NewGuid()));
    }

    [Fact]
    public async Task InvitesGoOnlyToFriendsWithAnEventAndAnInboxEntry()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);

        var outcome = await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id), Id(_peach.Id), "non-un-id", Id(_mario.Id)]);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Contains(
            _server.SentTo("s-luigi"),
            payload => payload == JsonSerializer.Serialize(SocialEvent.MatchInvite(Id(room), "Mario")));
        Assert.DoesNotContain(_server.SentTo("s-peach"), payload => payload.Contains("MatchInvite", StringComparison.Ordinal));
        Assert.DoesNotContain(_server.SentTo("s-mario"), payload => payload.Contains("MatchInvite", StringComparison.Ordinal));
        AssertConflict(MatchReasons.NotInvited, _match.Join(_peach.Id, room));
    }

    [Fact]
    public async Task OnlyTheCreatorInvitesWhileWaiting()
    {
        var room = await RoomWithLuigiAsync();
        await TestRecommendations.MakeFriendsAsync(_friends, _luigi.Id, _peach.Id);

        AssertConflict(MatchReasons.NotCreator, await _match.InviteAsync(_luigi.Id, room, [Id(_peach.Id)]));
        AssertConflict(MatchReasons.Closed, await _match.InviteAsync(_mario.Id, Guid.NewGuid(), [Id(_luigi.Id)]));

        _match.Start(_mario.Id, room, AnyTitle);
        AssertConflict(MatchReasons.Started, await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]));
    }

    [Fact]
    public async Task InvitesBeyondTheLimitAre429()
    {
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        var friends = new List<string>();
        for (var i = 0; i < 21; i++)
        {
            var friend = _server.AddUser("Amico" + i);
            await TestRecommendations.MakeFriendsAsync(_friends, friend.Id, _mario.Id);
            friends.Add(Id(friend.Id));
        }

        Assert.Equal(HubStatus.RateLimited, (await _match.InviteAsync(_mario.Id, room, friends)).Status);
        // I primi 20 sono stati invitati.
        Assert.Equal(HubStatus.Ok, _match.Join(Guid.Parse(friends[0]), room).Status);
        AssertConflict(MatchReasons.NotInvited, _match.Join(Guid.Parse(friends[20]), room));
    }

    [Fact]
    public async Task JoiningTellsWhyNot()
    {
        var room = await RoomWithLuigiAsync();

        // Di nuovo: già dentro.
        Assert.Equal(HubStatus.Ok, _match.Join(_luigi.Id, room).Status);
        AssertConflict(MatchReasons.Closed, _match.Join(_luigi.Id, Guid.NewGuid()));

        // Peach invitata ma già in un'altra sala aperta.
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id);
        await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]);
        var peachRoom = _match.Open(_peach.Id).State!.RoomId;
        AssertConflict(MatchReasons.InAnotherRoom, _match.Join(_peach.Id, room), peachRoom);
    }

    [Fact]
    public async Task OnlyTheFirstInvitesOfARequestAreConsidered()
    {
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        var ids = new List<string>();
        // I primi 50 non sono amici: vengono ignorati senza toccare il limite degli inviti.
        for (var i = 0; i < MatchService.MaxInvitesPerRequest; i++)
        {
            ids.Add(Id(_server.AddUser("Estraneo" + i).Id));
        }

        var beyondTheCap = _server.AddUser("Amico");
        await TestRecommendations.MakeFriendsAsync(_friends, beyondTheCap.Id, _mario.Id);
        ids.Add(Id(beyondTheCap.Id));

        Assert.Equal(HubStatus.Ok, (await _match.InviteAsync(_mario.Id, room, ids)).Status);
        AssertConflict(MatchReasons.NotInvited, _match.Join(beyondTheCap.Id, room));
    }

    [Fact]
    public async Task StartingARoomThatClosesWhileDrawingAnswersClosed()
    {
        var room = await RoomWithLuigiAsync();
        _server.MatchCandidates.Add(new MatchCandidate(Guid.NewGuid(), true, null));
        _server.OnMatchCandidates = () => _match.Leave(_mario.Id, room);

        AssertConflict(MatchReasons.Closed, _match.Start(_mario.Id, room, AnyTitle));

        var state = _match.Get(_luigi.Id, room).State!;
        Assert.Equal(MatchPhases.Closed, state.Phase);
        Assert.Equal(MatchClosedReasons.CreatorLeft, state.ClosedReason);
        Assert.Empty(state.Stack);
    }

    [Fact]
    public async Task MembersHearWhoJoins()
    {
        var room = await RoomWithLuigiAsync();

        var update = Updates("s-mario")[^1];
        Assert.Equal(Id(room), update.RoomId);
        Assert.Equal(2, update.Members.Count);
        Assert.NotEmpty(Updates("s-luigi"));
    }

    [Fact]
    public async Task OnlyTheCreatorStartsWithAFriend()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotEnoughMembers, _match.Start(_mario.Id, room, AnyTitle));

        await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id)]);
        _match.Join(_luigi.Id, room);
        AssertConflict(MatchReasons.NotCreator, _match.Start(_luigi.Id, room, AnyTitle));
        AssertConflict(MatchReasons.Closed, _match.Start(_mario.Id, Guid.NewGuid(), AnyTitle));
    }

    [Fact]
    public async Task StartingDrawsTheStackForTheMembers()
    {
        var room = await RoomWithLuigiAsync();
        var dune = new MatchCandidate(Guid.NewGuid(), true, null);
        var alien = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.AddRange([dune, alien]);
        _server.Watched[(_luigi.Id, dune.Id)] = DateTimeOffset.UnixEpoch;

        var outcome = _match.Start(_mario.Id, room, AnyTitle);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Equal(MatchPhases.Voting, outcome.State!.Phase);
        Assert.Equal(new[] { Id(alien.Id) }, outcome.State.Stack);
        Assert.Equal(_mario.Id, Assert.Single(_server.MatchQueries).UserId);
        // L'ingresso di luigi è appena partito: lo stato nuovo arriva dopo PushInterval.
        _time.Advance(MatchService.PushInterval);
        Assert.Equal(new[] { Id(alien.Id) }, Updates("s-luigi")[^1].Stack);
        AssertConflict(MatchReasons.Started, _match.Start(_mario.Id, room, AnyTitle));
    }

    [Fact]
    public async Task UpdatesAreAtMostOneEvery250Milliseconds()
    {
        var room = await RoomWithLuigiAsync();
        // L'ingresso di luigi è partito subito; questi due aspettano e partono insieme.
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id);
        await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]);
        var before = Updates("s-mario").Count;
        _match.Join(_peach.Id, room);
        _match.Leave(_peach.Id, room);
        Assert.Equal(before, Updates("s-mario").Count);

        _time.Advance(MatchService.PushInterval);

        var updates = Updates("s-mario");
        Assert.Equal(before + 1, updates.Count);
        Assert.Equal(2, updates[^1].Members.Count);
        Assert.Equal(_match.Get(_mario.Id, room).State!.Rev, updates[^1].Rev);

        // Dopo una pausa il primo cambio parte subito.
        _time.Advance(TimeSpan.FromSeconds(1));
        _match.Leave(_luigi.Id, room);
        Assert.Single(Updates("s-mario")[^1].Members);
    }

    [Fact]
    public async Task LeavingRemovesTheMemberAndAnUnknownRoomIsFine()
    {
        var room = await RoomWithLuigiAsync();

        _match.Leave(_luigi.Id, room);
        _match.Leave(_luigi.Id, room);
        _match.Leave(_luigi.Id, Guid.NewGuid());

        AssertConflict(MatchReasons.NotMember, _match.Get(_luigi.Id, room));
        Assert.Single(_match.Get(_mario.Id, room).State!.Members);
    }

    [Fact]
    public async Task TheCreatorLeavingClosesTheRoom()
    {
        var room = await RoomWithLuigiAsync();

        _match.Leave(_mario.Id, room);
        _time.Advance(MatchService.PushInterval);

        var state = _match.Get(_luigi.Id, room).State!;
        Assert.Equal(MatchPhases.Closed, state.Phase);
        Assert.Equal(MatchClosedReasons.CreatorLeft, state.ClosedReason);
        Assert.Equal(MatchPhases.Closed, Updates("s-luigi")[^1].Phase);
        // Una sala chiusa non conta più: si può aprirne un'altra.
        Assert.Equal(HubStatus.Ok, _match.Open(_luigi.Id).Status);
    }

    private async Task<(Guid Room, Guid Dune, Guid Alien)> VotingRoomAsync()
    {
        var room = await RoomWithLuigiAsync();
        var dune = new MatchCandidate(Guid.NewGuid(), true, null);
        var alien = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.AddRange([dune, alien]);
        Assert.Equal(HubStatus.Ok, _match.Start(_mario.Id, room, AnyTitle).Status);
        return (room, dune.Id, alien.Id);
    }

    [Fact]
    public async Task VotesMakeMatchesForEveryone()
    {
        var (room, dune, _) = await VotingRoomAsync();

        Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, dune, true).Status);
        Assert.Equal(HubStatus.Ok, _match.Vote(_luigi.Id, room, dune, true).Status);
        _time.Advance(MatchService.PushInterval);

        Assert.Equal(new[] { Id(dune) }, _match.Get(_luigi.Id, room).State!.Matches);
        Assert.Equal(new[] { Id(dune) }, Updates("s-luigi")[^1].Matches);
    }

    [Fact]
    public async Task VotesTellWhyNot()
    {
        var (room, dune, alien) = await VotingRoomAsync();

        AssertConflict(MatchReasons.NotNext, _match.Vote(_mario.Id, room, alien, true));
        AssertConflict(MatchReasons.NotMember, _match.Vote(_peach.Id, room, dune, true));
        AssertConflict(MatchReasons.Closed, _match.Vote(_mario.Id, Guid.NewGuid(), dune, true));

        var waiting = Guid.Parse(_match.Open(_peach.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotStarted, _match.Vote(_peach.Id, waiting, dune, true));
    }

    [Fact]
    public async Task VotesBeyondFourASecondAre429()
    {
        var room = await RoomWithLuigiAsync();
        for (var i = 0; i < 6; i++)
        {
            _server.MatchCandidates.Add(new MatchCandidate(Guid.NewGuid(), true, null));
        }

        var stack = _match.Start(_mario.Id, room, AnyTitle).State!.Stack.Select(Guid.Parse).ToList();
        for (var i = 0; i < 4; i++)
        {
            Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, stack[i], false).Status);
        }

        Assert.Equal(HubStatus.RateLimited, _match.Vote(_mario.Id, room, stack[4], false).Status);
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, stack[4], false).Status);
    }

    [Fact]
    public async Task UpdatesCarryCountsNotVotes()
    {
        var (room, dune, alien) = await VotingRoomAsync();
        _match.Vote(_mario.Id, room, dune, true);
        _match.Vote(_mario.Id, room, alien, false);
        _match.Vote(_luigi.Id, room, dune, false);
        _match.Vote(_luigi.Id, room, alien, false);
        _time.Advance(MatchService.PushInterval);

        var update = Updates("s-luigi")[^1];
        Assert.All(update.Members, member => Assert.Equal(2, member.Voted));
        Assert.Empty(update.Matches);
        // Su due membri basta un sì per un quasi match; non si dice di chi.
        Assert.Equal(new MatchNearMatchDto(Id(dune), 1, 2), Assert.Single(update.NearMatches));
        Assert.All(_server.SentTo("s-luigi"), payload => Assert.DoesNotContain("\"Votes\"", payload, StringComparison.Ordinal));
    }

    [Fact]
    public async Task MoreNeedsEveryoneToHaveFinished()
    {
        var (room, dune, alien) = await VotingRoomAsync();
        AssertConflict(MatchReasons.NotFinished, _match.More(_mario.Id, room));

        foreach (var user in new[] { _mario.Id, _luigi.Id })
        {
            _match.Vote(user, room, dune, false);
            _match.Vote(user, room, alien, false);
        }

        AssertConflict(MatchReasons.NotCreator, _match.More(_luigi.Id, room));

        // Niente di nuovo: pila e Rev restano.
        var rev = _match.Get(_mario.Id, room).State!.Rev;
        var same = _match.More(_mario.Id, room);
        Assert.Equal(HubStatus.Ok, same.Status);
        Assert.Equal(rev, same.State!.Rev);
        Assert.Equal(2, same.State.Stack.Count);
        // La query non ripesca i titoli già mostrati.
        Assert.True(_server.MatchQueries[^1].Exclude.ToHashSet().SetEquals([dune, alien]));

        var heat = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.Add(heat);
        var more = _match.More(_mario.Id, room);
        Assert.Equal(new[] { Id(dune), Id(alien), Id(heat.Id) }, more.State!.Stack);
    }

    [Fact]
    public async Task MoreIsOnlyWhileVoting()
    {
        var room = await RoomWithLuigiAsync();
        AssertConflict(MatchReasons.NotStarted, _match.More(_mario.Id, room));
        AssertConflict(MatchReasons.Closed, _match.More(_mario.Id, Guid.NewGuid()));
    }

    [Fact]
    public async Task ThePartyLetsTheMembersInAndClosesTheRoom()
    {
        var (room, dune, _) = await VotingRoomAsync();
        // Un avviso in attesa: il party lo scavalca e manda subito.
        _match.Vote(_mario.Id, room, dune, true);
        var group = Guid.NewGuid();
        _parties.Register(group, _mario.Id, PartyModes.Private);

        Assert.Equal(HubStatus.Ok, _match.Party(_mario.Id, room, group).Status);

        Assert.True(_parties.IsVisible(group, _luigi.Id, _ => false));
        var update = Updates("s-luigi")[^1];
        Assert.Equal(MatchPhases.Closed, update.Phase);
        Assert.Equal(MatchClosedReasons.PartyStarted, update.ClosedReason);
        Assert.Equal(Id(group), update.PartyGroupId);
        Assert.Equal(Id(group), _match.Get(_luigi.Id, room).State!.PartyGroupId);
    }

    [Fact]
    public async Task OnlyTheCreatorStartsTheirOwnParty()
    {
        var (room, _, _) = await VotingRoomAsync();
        var mine = Guid.NewGuid();
        var luigis = Guid.NewGuid();
        _parties.Register(mine, _mario.Id, PartyModes.Private);
        _parties.Register(luigis, _luigi.Id, PartyModes.Private);

        AssertConflict(MatchReasons.NotCreator, _match.Party(_luigi.Id, room, luigis));
        AssertConflict(MatchReasons.NotYourParty, _match.Party(_mario.Id, room, luigis));
        AssertConflict(MatchReasons.NotYourParty, _match.Party(_mario.Id, room, Guid.NewGuid()));
        AssertConflict(MatchReasons.Closed, _match.Party(_mario.Id, Guid.NewGuid(), mine));

        var waiting = Guid.Parse(_match.Open(_peach.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotStarted, _match.Party(_peach.Id, waiting, mine));
    }

    [Fact]
    public async Task AMemberWithoutSessionsLeavesAfterTheGrace()
    {
        var room = await RoomWithLuigiAsync();
        var luigiSession = _server.Sessions.Single(s => s.UserId == _luigi.Id);
        _server.Sessions.Remove(luigiSession);

        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(2, _match.Get(_mario.Id, room).State!.Members.Count);

        // Riconnesso in tempo: si riparte da capo.
        _server.Sessions.Add(luigiSession);
        _match.Cleanup();
        _server.Sessions.Remove(luigiSession);
        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(2, _match.Get(_mario.Id, room).State!.Members.Count);

        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(1, _match.Cleanup());
        Assert.Single(_match.Get(_mario.Id, room).State!.Members);
    }

    [Fact]
    public async Task TheCreatorWithoutSessionsClosesTheRoom()
    {
        var room = await RoomWithLuigiAsync();
        _server.Sessions.RemoveAll(s => s.UserId == _mario.Id);

        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace);
        _match.Cleanup();

        Assert.Equal(MatchClosedReasons.CreatorLeft, _match.Get(_luigi.Id, room).State!.ClosedReason);
    }

    [Fact]
    public async Task AnIdleRoomClosesAfterAnHourAndIsForgottenFiveMinutesLater()
    {
        var room = await RoomWithLuigiAsync();

        _time.Advance(MatchService.InactiveAfter - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(MatchPhases.Waiting, _match.Get(_mario.Id, room).State!.Phase);

        _time.Advance(TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(MatchClosedReasons.Inactive, _match.Get(_mario.Id, room).State!.ClosedReason);

        _time.Advance(MatchService.ClosedKept);
        _match.Cleanup();
        AssertConflict(MatchReasons.NotMember, _match.Get(_mario.Id, room));
    }
}
