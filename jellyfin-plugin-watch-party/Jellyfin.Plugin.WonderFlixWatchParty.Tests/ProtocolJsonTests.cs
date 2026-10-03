using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ProtocolJsonTests
{
    [Fact]
    public void StampedEventUsesProtocolNamesAndSkipsEmptyFields()
    {
        var stamped = new StampedEvent
        {
            Id = "e1",
            GroupId = "g1",
            Type = EventTypes.Chat,
            UserId = "u1",
            UserName = "Mario",
            SentAt = "2026-10-02T21:14:03.512Z",
            Text = "ciao",
        };
        Assert.Equal(
            "{\"Protocol\":1,\"Id\":\"e1\",\"GroupId\":\"g1\",\"Type\":\"Chat\",\"UserId\":\"u1\","
            + "\"UserName\":\"Mario\",\"SentAt\":\"2026-10-02T21:14:03.512Z\",\"Text\":\"ciao\"}",
            JsonSerializer.Serialize(stamped));
    }

    [Fact]
    public void EventRequestReadsAnyCaseOfNames()
    {
        // Come i controller di Jellyfin: nomi delle proprietà senza maiuscole.
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var request = JsonSerializer.Deserialize<EventRequest>(
            "{\"type\":\"Action\",\"Action\":\"Seek\",\"PositionTicks\":600000000}", options)!;
        Assert.Equal("Action", request.Type);
        Assert.Equal("Seek", request.Action);
        Assert.Equal(600000000L, request.PositionTicks);
    }

    [Fact]
    public void InfoAndJoinResponsesUseProtocolNames()
    {
        Assert.Equal(
            "{\"Version\":\"1.1.0\",\"Protocol\":1,\"Features\":[\"friends\"]}",
            JsonSerializer.Serialize(new InfoResponse("1.1.0", 1, ["friends"])));
        Assert.Equal("{\"Messages\":[]}", JsonSerializer.Serialize(new JoinResponse([])));
    }

    [Fact]
    public void SocialEventsHaveNoGroupAndSkipEmptyFields()
    {
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"FriendRequest\",\"FromUserId\":\"u1\",\"FromName\":\"Mario\"}",
            JsonSerializer.Serialize(SocialEvent.FriendRequest("u1", "Mario")));
        Assert.Equal("{\"Protocol\":1,\"Type\":\"FriendsChanged\"}", JsonSerializer.Serialize(SocialEvent.FriendsChanged()));
    }

    [Fact]
    public void FriendResponsesUseProtocolNames()
    {
        var friends = new FriendsResponse(
            [new FriendEntry("u2", "Luigi", true, null)],
            [new PersonEntry("u3", "Peach")],
            []);
        Assert.Equal(
            "{\"Friends\":[{\"UserId\":\"u2\",\"Name\":\"Luigi\",\"Online\":true,\"Party\":null}],"
            + "\"Incoming\":[{\"UserId\":\"u3\",\"Name\":\"Peach\"}],\"Outgoing\":[]}",
            JsonSerializer.Serialize(friends));
        Assert.Equal(
            "{\"UserId\":\"u2\",\"Name\":\"Luigi\",\"Relation\":\"Friend\"}",
            JsonSerializer.Serialize(new UserSearchResult("u2", "Luigi", FriendRelations.Friend)));
    }

    [Fact]
    public void PartyEventsAndResponsesUseProtocolNames()
    {
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"PartyStarted\",\"GroupId\":\"g1\",\"Name\":\"Dune\",\"Mode\":\"Friends\"}",
            JsonSerializer.Serialize(SocialEvent.PartyStarted("g1", "Dune", PartyModes.Friends)));
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"PartyInvite\",\"FromName\":\"Mario\",\"GroupId\":\"g1\",\"Name\":\"Dune\"}",
            JsonSerializer.Serialize(SocialEvent.PartyInvite("g1", "Dune", "Mario")));
        Assert.Equal("{\"Code\":\"K7PQ2X\"}", JsonSerializer.Serialize(new RegisterPartyResponse("K7PQ2X")));
        Assert.Equal(
            "{\"GroupId\":\"g1\",\"Name\":\"Dune\",\"State\":\"Idle\",\"Participants\":[\"Mario\"],\"Mode\":\"Private\"}",
            JsonSerializer.Serialize(new PartySummary("g1", "Dune", "Idle", new[] { "Mario" }, PartyModes.Private)));
        Assert.Equal(
            "{\"Mode\":\"Public\",\"Code\":null}",
            JsonSerializer.Serialize(new PartyDetails(PartyModes.Public, null)));
        Assert.Equal("{\"GroupId\":\"g1\"}", JsonSerializer.Serialize(new JoinByCodeResponse("g1")));
    }

    [Fact]
    public void PartyRequestsReadAnyCaseOfNames()
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        Assert.Equal("Friends", JsonSerializer.Deserialize<RegisterPartyRequest>("{\"mode\":\"Friends\"}", options)!.Mode);
        Assert.Equal("K7P-Q2X", JsonSerializer.Deserialize<JoinByCodeRequest>("{\"code\":\"K7P-Q2X\"}", options)!.Code);
        Assert.Equal(
            new[] { "u2", "u3" },
            JsonSerializer.Deserialize<InviteRequest>("{\"userIds\":[\"u2\",\"u3\"]}", options)!.UserIds);
    }

    [Fact]
    public void PartyModesAreExact()
    {
        Assert.True(PartyModes.IsValid("Public"));
        Assert.True(PartyModes.IsValid("Friends"));
        Assert.True(PartyModes.IsValid("Private"));
        Assert.False(PartyModes.IsValid("public"));
        Assert.False(PartyModes.IsValid(null));
    }
}
