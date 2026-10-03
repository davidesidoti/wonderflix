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
}
