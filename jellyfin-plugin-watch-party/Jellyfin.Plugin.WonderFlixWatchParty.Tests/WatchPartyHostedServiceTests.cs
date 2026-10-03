using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class WatchPartyHostedServiceTests
{
    [Fact]
    public async Task EndedSessionsLeaveAndEndedGroupsAreCleaned()
    {
        var server = new FakeServer();
        var time = new FakeTimeProvider();
        var hub = new PartyHub(
            server, server, server, new PartyRegistry(), new ChatHistory(), new RateLimiter(time), time,
            NullLogger<PartyHub>.Instance);
        var group = Guid.NewGuid();
        var mario = server.AddSession("s-mario", "Mario");
        var luigi = server.AddSession("s-luigi", "Luigi");
        server.Groups[group] = ["Mario", "Luigi"];
        hub.Join(mario, group);
        hub.Join(luigi, group);

        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        EventHandler<SessionEventArgs>? ended = null;
        stub.Handlers["add_SessionEnded"] = args =>
        {
            ended = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        using var folder = new TempFolder();
        var friends = new FriendService(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);
        using var presence = new PresenceTracker(friends, time, NullLogger<PresenceTracker>.Instance);
        var parties = new PartyService(
            new PartyDirectory(time), server, server, server, friends, new PartyRegistry(), server,
            new RateLimiter(time), NullLogger<PartyService>.Instance);
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, parties, time, NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(ended);

        ended(manager, new SessionEventArgs { SessionInfo = new SessionInfo(manager, NullLogger.Instance) { Id = "s-luigi" } });
        await hub.PostAsync(mario, group, new EventRequest { Type = EventTypes.Chat, Text = "ciao" }, CancellationToken.None);
        Assert.Empty(server.Sent);

        // Il gruppo finisce: alla pulizia successiva registro e storico spariscono.
        server.Groups.Remove(group);
        time.Advance(WatchPartyHostedService.CleanupInterval);
        server.Groups[group] = ["Mario", "Luigi"];
        Assert.Empty(hub.Join(luigi, group).Value!);

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(stub.Calls, c => c.Name == "remove_SessionEnded");
    }

    [Fact]
    public async Task WonderFlixSessionsStartingOrEndingNotifyFriends()
    {
        var server = new FakeServer();
        var time = new FakeTimeProvider();
        var hub = new PartyHub(
            server, server, server, new PartyRegistry(), new ChatHistory(), new RateLimiter(time), time,
            NullLogger<PartyHub>.Instance);
        using var folder = new TempFolder();
        var friends = new FriendService(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);
        using var presence = new PresenceTracker(friends, time, NullLogger<PresenceTracker>.Instance);
        var mario = server.AddUser("Mario");
        var luigi = server.AddUser("Luigi");
        server.AddSession("s-luigi", luigi);
        await friends.RequestAsync(mario.Id, luigi.Id);
        await friends.AcceptAsync(luigi.Id, mario.Id);
        server.Sent.Clear();

        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        EventHandler<SessionEventArgs>? started = null;
        EventHandler<SessionEventArgs>? ended = null;
        stub.Handlers["add_SessionStarted"] = args =>
        {
            started = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        stub.Handlers["add_SessionEnded"] = args =>
        {
            ended = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        var parties = new PartyService(
            new PartyDirectory(time), server, server, server, friends, new PartyRegistry(), server,
            new RateLimiter(time), NullLogger<PartyService>.Instance);
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, parties, time, NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(started);
        Assert.NotNull(ended);
        SessionEventArgs Args(string client) => new()
        {
            SessionInfo = new SessionInfo(manager, NullLogger.Instance) { Id = "s-mario", Client = client, UserId = mario.Id },
        };

        started(manager, Args("Jellyfin Web"));
        time.Advance(PresenceTracker.Delay);
        Assert.Empty(server.Sent);

        started(manager, Args("WonderFlix"));
        time.Advance(PresenceTracker.Delay);
        Assert.Single(server.SentTo("s-luigi"));

        ended(manager, Args("WonderFlix"));
        time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, server.SentTo("s-luigi").Count);

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(stub.Calls, c => c.Name == "remove_SessionStarted");
    }
}
