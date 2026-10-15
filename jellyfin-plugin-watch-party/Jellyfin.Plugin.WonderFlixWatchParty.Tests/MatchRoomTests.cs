using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchRoomTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 14, 20, 0, 0, TimeSpan.Zero);
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly Guid _daisy = Guid.NewGuid();
    private readonly Guid _dune = Guid.NewGuid();
    private readonly Guid _alien = Guid.NewGuid();
    private readonly Guid _heat = Guid.NewGuid();

    private MatchRoom Room(params Guid[] guests)
    {
        var room = new MatchRoom(Guid.NewGuid(), _mario, "Mario", Now);
        foreach (var guest in guests)
        {
            room.Invite(guest);
            Assert.Null(room.Join(guest, guest == _luigi ? "Luigi" : "Ospite", Now));
        }

        return room;
    }

    private MatchRoom Voting(params Guid[] guests)
    {
        var room = Room(guests);
        room.Start(AnyTitle, [_dune, _alien, _heat], Now);
        return room;
    }

    private static IReadOnlyList<string> Ids(params Guid[] ids) => ids.Select(id => id.ToString("N")).ToList();

    [Fact]
    public void ARoomStartsWaitingWithTheCreator()
    {
        var room = Room();
        var state = room.Snapshot();

        Assert.Equal(MatchPhases.Waiting, state.Phase);
        Assert.Equal(_mario.ToString("N"), state.CreatorId);
        Assert.Equal("Mario", state.CreatorName);
        Assert.Equal(new MatchMemberDto(_mario.ToString("N"), "Mario", 0), Assert.Single(state.Members));
        Assert.Empty(state.Stack);
        Assert.Null(state.ClosedReason);
        Assert.True(room.IsOpen);
    }

    [Fact]
    public void OnlyInvitedUsersJoinWhileWaitingUpToEight()
    {
        var room = Room();
        Assert.Equal(MatchReasons.NotInvited, room.Join(_luigi, "Luigi", Now));

        room.Invite(_luigi);
        var rev = room.Rev;
        Assert.Null(room.Join(_luigi, "Luigi", Now));
        Assert.True(room.Rev > rev);

        // Di nuovo: già dentro, niente cambia.
        rev = room.Rev;
        Assert.Null(room.Join(_luigi, "Luigi", Now));
        Assert.Equal(rev, room.Rev);

        for (var i = room.MemberCount; i < MatchRoom.MaxMembers; i++)
        {
            var guest = Guid.NewGuid();
            room.Invite(guest);
            Assert.Null(room.Join(guest, "Ospite", Now));
        }

        room.Invite(_peach);
        Assert.Equal(MatchReasons.Full, room.Join(_peach, "Peach", Now));
    }

    [Fact]
    public void NobodyJoinsAfterTheStartOrWhileDrawing()
    {
        var drawing = Room();
        drawing.Invite(_luigi);
        drawing.Drawing = true;
        Assert.Equal(MatchReasons.Started, drawing.Join(_luigi, "Luigi", Now));

        var voting = Voting();
        voting.Invite(_luigi);
        Assert.Equal(MatchReasons.Started, voting.Join(_luigi, "Luigi", Now));

        voting.Close(MatchClosedReasons.Inactive, null, Now);
        Assert.Equal(MatchReasons.Closed, voting.Join(_luigi, "Luigi", Now));
    }

    [Fact]
    public void VotesGoInOrder()
    {
        var room = Voting(_luigi);

        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _alien, true, Now));
        Assert.Null(room.Vote(_mario, _dune, true, Now));
        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _dune, false, Now));
        Assert.Null(room.Vote(_mario, _alien, false, Now));
        Assert.Equal(MatchReasons.NotMember, room.Vote(_peach, _dune, true, Now));

        var members = room.Snapshot().Members;
        Assert.Equal(2, members[0].Voted);
        Assert.Equal(0, members[1].Voted);
    }

    [Fact]
    public void NoVotesBeforeTheStartOrAfterTheEnd()
    {
        var waiting = Room(_luigi);
        Assert.Equal(MatchReasons.NotStarted, waiting.Vote(_mario, _dune, true, Now));

        var room = Voting(_luigi);
        foreach (var item in new[] { _dune, _alien, _heat })
        {
            Assert.Null(room.Vote(_mario, item, true, Now));
        }

        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _dune, true, Now));

        room.Close(MatchClosedReasons.Inactive, null, Now);
        Assert.Equal(MatchReasons.Closed, room.Vote(_luigi, _dune, true, Now));
    }

    [Fact]
    public void AMatchIsATitleEveryoneLikes()
    {
        var room = Voting(_luigi);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_mario, _alien, true, Now);
        Assert.Empty(room.Snapshot().Matches);

        room.Vote(_luigi, _dune, false, Now);
        room.Vote(_luigi, _alien, true, Now);

        Assert.Equal(Ids(_alien), room.Snapshot().Matches);
    }

    [Fact]
    public void MatchesKeepTheOrderTheyCameOut()
    {
        var room = Voting(_luigi);
        room.Vote(_luigi, _dune, true, Now);
        room.Vote(_luigi, _alien, true, Now);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_mario, _alien, true, Now);

        Assert.Equal(Ids(_dune, _alien), room.Snapshot().Matches);
    }

    [Fact]
    public void AMemberLeavingCanMakeAMatch()
    {
        var room = Voting(_luigi, _peach);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_luigi, _dune, true, Now);
        room.Vote(_peach, _dune, false, Now);
        Assert.Empty(room.Snapshot().Matches);

        var rev = room.Rev;
        Assert.True(room.Remove(_peach));

        Assert.True(room.Rev > rev);
        Assert.Equal(Ids(_dune), room.Snapshot().Matches);
        Assert.False(room.IsMember(_peach));
        Assert.False(room.Remove(_peach));
    }

    [Fact]
    public void TheCreatorIsNotRemovedLikeTheOthers()
    {
        var room = Voting(_luigi);
        Assert.False(room.Remove(_mario));
        Assert.True(room.IsMember(_mario));
    }

    [Fact]
    public void AloneEveryYesIsAMatch()
    {
        var room = Voting(_luigi);
        room.Vote(_mario, _dune, true, Now);
        room.Remove(_luigi);

        Assert.Equal(Ids(_dune), room.Snapshot().Matches);
    }

    [Fact]
    public void NearMatchesComeOnlyWhenEveryoneHasFinished()
    {
        var room = Voting(_luigi, _peach);
        // Dune: 2 sì su 3; Alien: 1 su 3; Heat: 3 su 3 (match).
        Vote(room, _mario, true, true, true);
        Vote(room, _luigi, true, false, true);
        Assert.Empty(room.Snapshot().NearMatches);
        Assert.False(room.AllFinished);

        Vote(room, _peach, false, false, true);

        Assert.True(room.AllFinished);
        var state = room.Snapshot();
        Assert.Equal(Ids(_heat), state.Matches);
        Assert.Equal(new MatchNearMatchDto(_dune.ToString("N"), 2, 3), Assert.Single(state.NearMatches));
    }

    [Fact]
    public void NearMatchesGoFromTheMostLikedUpToFive()
    {
        var room = Room(_luigi);
        var stack = Enumerable.Range(0, 7).Select(_ => Guid.NewGuid()).ToList();
        room.Start(AnyTitle, stack, Now);
        // Su 2 membri la soglia è 1 sì: mario dice sì a tutti, luigi a nessuno.
        foreach (var item in stack)
        {
            room.Vote(_mario, item, true, Now);
            room.Vote(_luigi, item, false, Now);
        }

        var near = room.Snapshot().NearMatches;
        Assert.Equal(MatchRoom.MaxNearMatches, near.Count);
        Assert.Equal(stack.Take(5).Select(id => id.ToString("N")), near.Select(n => n.ItemId));
        Assert.All(near, n => Assert.Equal((1, 2), (n.Yes, n.Of)));
    }

    [Fact]
    public void TheMoreLikedComeFirstAmongNearMatches()
    {
        var room = Voting(_luigi, _peach, _daisy);
        // Quattro membri, soglia 2: Dune 2 sì, Alien 3 sì, Heat 1 sì.
        Vote(room, _mario, true, true, false);
        Vote(room, _luigi, true, true, false);
        Vote(room, _peach, false, true, true);
        Vote(room, _daisy, false, false, false);

        Assert.Equal(
            new[] { new MatchNearMatchDto(_alien.ToString("N"), 3, 4), new MatchNearMatchDto(_dune.ToString("N"), 2, 4) },
            room.Snapshot().NearMatches);
    }

    [Fact]
    public void MoreTitlesNeverRepeatOnes()
    {
        var room = Voting();
        var rev = room.Rev;

        Assert.False(room.AddToStack([_dune, _alien], Now));
        Assert.Equal(rev, room.Rev);

        var extra = Guid.NewGuid();
        Assert.True(room.AddToStack([_heat, extra], Now));
        Assert.Equal(Ids(_dune, _alien, _heat, extra), room.Snapshot().Stack);
        Assert.Contains(extra, room.Shown);
        Assert.True(room.Rev > rev);
    }

    [Fact]
    public void AnEmptyStackIsFinishedWithNoNearMatches()
    {
        var room = Room(_luigi);
        room.Start(AnyTitle, [], Now);

        Assert.True(room.AllFinished);
        Assert.Empty(room.Snapshot().NearMatches);
        Assert.Equal(AnyTitle, room.Filters);
    }

    [Fact]
    public void ClosingKeepsTheMembersAndTheParty()
    {
        var room = Voting(_luigi);
        var party = Guid.NewGuid();
        room.Close(MatchClosedReasons.PartyStarted, party, Now.AddMinutes(1));

        var state = room.Snapshot();
        Assert.Equal(MatchPhases.Closed, state.Phase);
        Assert.Equal(MatchClosedReasons.PartyStarted, state.ClosedReason);
        Assert.Equal(party.ToString("N"), state.PartyGroupId);
        Assert.Equal(2, state.Members.Count);
        Assert.Equal(Now.AddMinutes(1), room.ClosedAt);
        Assert.False(room.IsOpen);

        // Una seconda chiusura non cambia niente.
        var rev = room.Rev;
        room.Close(MatchClosedReasons.Inactive, null, Now.AddMinutes(2));
        Assert.Equal(rev, room.Rev);
        Assert.Equal(MatchClosedReasons.PartyStarted, room.ClosedReason);
    }

    [Fact]
    public void AbsentMembersCountFromWhenTheyLostTheirSessions()
    {
        var room = Voting(_luigi);
        var grace = TimeSpan.FromSeconds(60);

        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now, grace));
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(59), grace));
        Assert.Equal(new[] { _luigi }, room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(60), grace));

        // Riconnesso: si riparte da capo.
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario, _luigi }, Now.AddSeconds(61), grace));
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(100), grace));
    }

    [Fact]
    public void TheSnapshotNeverHasTheVotes()
    {
        var room = Voting(_luigi);
        Vote(room, _mario, true, false, true);
        Vote(room, _luigi, false, false, true);

        var json = JsonSerializer.Serialize(room.Snapshot());

        Assert.DoesNotContain("Yes\":true", json, StringComparison.Ordinal);
        Assert.DoesNotContain("Votes", json, StringComparison.Ordinal);
        Assert.Equal(
            "{\"RoomId\":\"" + room.Id.ToString("N") + "\",\"Rev\":" + room.Rev + ",\"Phase\":\"Voting\","
            + "\"CreatorId\":\"" + _mario.ToString("N") + "\",\"CreatorName\":\"Mario\","
            + "\"Members\":[{\"UserId\":\"" + _mario.ToString("N") + "\",\"Name\":\"Mario\",\"Voted\":3},"
            + "{\"UserId\":\"" + _luigi.ToString("N") + "\",\"Name\":\"Luigi\",\"Voted\":3}],"
            + "\"Stack\":[\"" + _dune.ToString("N") + "\",\"" + _alien.ToString("N") + "\",\"" + _heat.ToString("N") + "\"],"
            + "\"Matches\":[\"" + _heat.ToString("N") + "\"],"
            + "\"NearMatches\":[{\"ItemId\":\"" + _dune.ToString("N") + "\",\"Yes\":1,\"Of\":2}]}",
            json);
    }

    private void Vote(MatchRoom room, Guid user, params bool[] answers)
    {
        var stack = new[] { _dune, _alien, _heat };
        for (var i = 0; i < answers.Length; i++)
        {
            Assert.Null(room.Vote(user, stack[i], answers[i], Now));
        }
    }
}
