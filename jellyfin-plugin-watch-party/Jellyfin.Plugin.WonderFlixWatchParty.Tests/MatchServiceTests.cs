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

    private static void AssertConflict(string reason, MatchOutcome outcome)
    {
        Assert.Equal(HubStatus.Conflict, outcome.Status);
        Assert.Equal(reason, outcome.Reason);
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
        _match.Open(_mario.Id);
        AssertConflict(MatchReasons.InAnotherRoom, _match.Open(_mario.Id));
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
        _match.Open(_peach.Id);
        AssertConflict(MatchReasons.InAnotherRoom, _match.Join(_peach.Id, room));
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
}
