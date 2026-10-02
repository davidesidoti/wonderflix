using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyHubTests
{
    private static readonly Guid Group = Guid.Parse("9a1e2b3c-4d5e-6f70-8192-a3b4c5d6e7f8");

    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 2, 21, 14, 3, 512, TimeSpan.Zero));
    private readonly PartyHub _hub;
    private readonly CallerSession _mario;
    private readonly CallerSession _luigi;

    public PartyHubTests()
    {
        _hub = new PartyHub(
            _server, _server, _server, new PartyRegistry(), new ChatHistory(), new RateLimiter(_time), _time,
            NullLogger<PartyHub>.Instance);
        _mario = _server.AddSession("s-mario", "Mario");
        _luigi = _server.AddSession("s-luigi", "Luigi");
        _server.Groups[Group] = ["Mario", "Luigi"];
    }

    private static EventRequest Chat(string text) => new() { Type = EventTypes.Chat, Text = text };

    private CallerSession AddPeach()
    {
        _server.Groups[Group].Add("Peach");
        return _server.AddSession("s-peach", "Peach");
    }

    [Fact]
    public void JoinOutsideTheGroupIsForbidden()
    {
        var bowser = _server.AddSession("s-bowser", "Bowser");
        Assert.Equal(HubStatus.Forbidden, _hub.Join(bowser, Group).Status);
        Assert.Equal(HubStatus.Forbidden, _hub.Join(_mario, Guid.NewGuid()).Status);
    }

    [Fact]
    public async Task JoinReturnsTheChatHistory()
    {
        Assert.Equal(HubStatus.Ok, _hub.Join(_luigi, Group).Status);
        await _hub.PostAsync(_luigi, Group, Chat("ciao"), CancellationToken.None);
        await _hub.PostAsync(_luigi, Group, new EventRequest { Type = EventTypes.Reaction, Reaction = "joy" }, CancellationToken.None);
        var joined = _hub.Join(_mario, Group);
        Assert.Equal(HubStatus.Ok, joined.Status);
        Assert.Equal("ciao", Assert.Single(joined.Value!).Text);
    }

    [Fact]
    public async Task NamesComeFromTheSessionNotFromTheBody()
    {
        _hub.Join(_mario, Group);
        var result = await _hub.PostAsync(_mario, Group, Chat("che scena"), CancellationToken.None);
        Assert.Equal(HubStatus.Ok, result.Status);
        var stamped = result.Value!;
        Assert.Equal("Mario", stamped.UserName);
        Assert.Equal(_mario.UserId.ToString("N"), stamped.UserId);
        Assert.Equal(Group.ToString("N"), stamped.GroupId);
        Assert.Equal("2026-10-02T21:14:03.512Z", stamped.SentAt);
        Assert.Equal(32, stamped.Id.Length);
        Assert.Equal(WatchPartyProtocol.Version, stamped.Protocol);
        Assert.Equal("che scena", stamped.Text);
    }

    [Fact]
    public async Task EventsGoToTheOtherSessionsOnly()
    {
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        await _hub.PostAsync(
            _mario, Group, new EventRequest { Type = EventTypes.Action, Action = "Seek", PositionTicks = 600000000 },
            CancellationToken.None);
        var (sessionId, payload) = Assert.Single(_server.Sent);
        Assert.Equal("s-luigi", sessionId);
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("Action", json.GetProperty("Type").GetString());
        Assert.Equal("Seek", json.GetProperty("Action").GetString());
        Assert.Equal(600000000L, json.GetProperty("PositionTicks").GetInt64());
        Assert.Equal("Mario", json.GetProperty("UserName").GetString());
        Assert.False(json.TryGetProperty("Text", out _));
    }

    [Fact]
    public async Task SessionsThatLeftTheGroupOrEndedAreDropped()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _server.Groups[Group].Remove("Luigi");
        _server.Sessions.Remove(peach);
        await _hub.PostAsync(_mario, Group, Chat("ci siete?"), CancellationToken.None);
        Assert.Empty(_server.Sent);
        // Luigi torna nel gruppo SyncPlay ma non si è registrato di nuovo.
        _server.Groups[Group].Add("Luigi");
        await _hub.PostAsync(_mario, Group, Chat("e adesso?"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task AFailedSendDoesNotStopTheOthers()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _server.Failing.Add("s-luigi");
        var result = await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal("s-peach", Assert.Single(_server.Sent).SessionId);
    }

    [Fact]
    public async Task InvalidForbiddenAndRateLimited()
    {
        Assert.Equal(HubStatus.Invalid, (await _hub.PostAsync(_mario, Group, Chat("  "), CancellationToken.None)).Status);
        var bowser = _server.AddSession("s-bowser", "Bowser");
        Assert.Equal(HubStatus.Forbidden, (await _hub.PostAsync(bowser, Group, Chat("ciao"), CancellationToken.None)).Status);
        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(HubStatus.Ok, (await _hub.PostAsync(_mario, Group, Chat($"m{i}"), CancellationToken.None)).Status);
        }

        var limited = await _hub.PostAsync(_mario, Group, Chat("troppo"), CancellationToken.None);
        Assert.Equal(HubStatus.RateLimited, limited.Status);
        Assert.Equal(5, _hub.Join(_luigi, Group).Value!.Count);
    }

    [Fact]
    public async Task PostingRegistersTheSender()
    {
        _hub.Join(_luigi, Group);
        await _hub.PostAsync(_mario, Group, new EventRequest { Type = EventTypes.Reaction, Reaction = "joy" }, CancellationToken.None);
        _server.Sent.Clear();
        await _hub.PostAsync(_luigi, Group, Chat("ciao Mario"), CancellationToken.None);
        Assert.Equal("s-mario", Assert.Single(_server.Sent).SessionId);
    }

    [Fact]
    public async Task LeaveAndRemoveSessionStopForwarding()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _hub.Leave(_luigi, Group);
        _hub.RemoveSession("s-peach");
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task CleanupDropsEndedGroupsAndTheirHistory()
    {
        _hub.Join(_mario, Group);
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal(0, _hub.Cleanup());
        _server.Groups.Remove(Group);
        Assert.Equal(1, _hub.Cleanup());
        _server.Groups[Group] = ["Mario", "Luigi"];
        Assert.Empty(_hub.Join(_mario, Group).Value!);
    }

    [Fact]
    public async Task CleanupDropsGroupsWithoutLiveSessions()
    {
        _hub.Join(_mario, Group);
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        _server.Sessions.Remove(_mario);
        Assert.Equal(1, _hub.Cleanup());
        Assert.Empty(_hub.Join(_luigi, Group).Value!);
    }
}
