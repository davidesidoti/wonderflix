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

    [Fact]
    public void InboxEntriesSkipTheFieldsOfOtherTypes()
    {
        var at = new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);
        var entry = new InboxEntry
        {
            Id = "e1",
            Seq = 3,
            Type = InboxEntryTypes.Announcement,
            CreatedAt = at,
            Text = "Stasera manutenzione",
        };

        var json = JsonDocument.Parse(JsonSerializer.Serialize(entry)).RootElement;

        Assert.Equal(
            new[] { "Id", "Seq", "Type", "CreatedAt", "Read", "Text" },
            json.EnumerateObject().Select(p => p.Name));
        Assert.Equal(3, json.GetProperty("Seq").GetInt64());
        Assert.Equal(at, json.GetProperty("CreatedAt").GetDateTimeOffset());
        Assert.False(json.GetProperty("Read").GetBoolean());
        Assert.Equal("{\"Entries\":[],\"Unread\":0}", JsonSerializer.Serialize(new InboxResponse([], 0)));
        Assert.Equal("{\"Recipients\":4}", JsonSerializer.Serialize(new AnnouncementResponse(4)));
        Assert.Equal("{\"Protocol\":1,\"Type\":\"InboxChanged\"}", JsonSerializer.Serialize(SocialEvent.InboxChanged()));
    }

    [Fact]
    public void InboxRequestsReadAnyCaseOfNames()
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        Assert.Equal(42L, JsonSerializer.Deserialize<InboxReadRequest>("{\"upTo\":42}", options)!.UpTo);
        Assert.Equal("ciao", JsonSerializer.Deserialize<AnnouncementRequest>("{\"text\":\"ciao\"}", options)!.Text);
    }

    [Fact]
    public void NewTitlesEntriesUseProtocolNames()
    {
        var entry = new InboxEntry
        {
            Id = "e2",
            Seq = 4,
            Type = InboxEntryTypes.NewTitles,
            CreatedAt = new DateTimeOffset(2026, 10, 4, 9, 0, 0, TimeSpan.Zero),
            Movies =
            [
                new NewTitleMovie { ItemId = "m1", Name = "Dune", Year = 2024 },
                new NewTitleMovie { ItemId = "m2", Name = "Senza anno" },
            ],
            Series =
            [
                new NewTitleSeries
                {
                    SeriesId = "s1",
                    Name = "The Bear",
                    Episodes = [new NewTitleEpisode { Season = 3, Episode = 1 }, new NewTitleEpisode()],
                },
            ],
            More = 2,
        };

        var json = JsonDocument.Parse(JsonSerializer.Serialize(entry)).RootElement;

        Assert.Equal(
            new[] { "Id", "Seq", "Type", "CreatedAt", "Read", "Movies", "Series", "More" },
            json.EnumerateObject().Select(p => p.Name));
        Assert.Equal("{\"ItemId\":\"m1\",\"Name\":\"Dune\",\"Year\":2024}", json.GetProperty("Movies")[0].GetRawText());
        Assert.Equal("{\"ItemId\":\"m2\",\"Name\":\"Senza anno\"}", json.GetProperty("Movies")[1].GetRawText());
        var episodes = json.GetProperty("Series")[0].GetProperty("Episodes");
        Assert.Equal("{\"Season\":3,\"Episode\":1}", episodes[0].GetRawText());
        Assert.Equal("{}", episodes[1].GetRawText());
        Assert.Equal("{\"Enabled\":true,\"Pending\":3}", JsonSerializer.Serialize(new NewTitlesStatus(true, 3)));
        Assert.Equal("{\"Titles\":5,\"Recipients\":2}", JsonSerializer.Serialize(new NewTitlesSendResponse(5, 2)));
    }
}
