using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging;
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
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        var inbox = TestInbox.Create(server, folder, time);
        var parties = new PartyService(
            directory, server, server, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, parties, inbox, time, NullLogger<WatchPartyHostedService>.Instance);
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
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        var inbox = TestInbox.Create(server, folder, time);
        var parties = new PartyService(
            directory, server, server, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, parties, inbox, time, NullLogger<WatchPartyHostedService>.Instance);
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

    [Fact]
    public async Task CleanupAlsoDropsExpiredNotifications()
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
        var inbox = TestInbox.Create(server, folder, time);
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        var parties = new PartyService(
            directory, server, server, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        var mario = server.AddUser("Mario");
        await inbox.AnnounceAsync("vecchio");
        // Prima di creare il timer della pulizia: un timer periodico
        // scatterebbe una volta per ogni periodo saltato.
        time.Advance(InboxService.MaxAge + TimeSpan.FromMinutes(1));
        using var service = new WatchPartyHostedService(
            InterfaceStub<ISessionManager>.Create().Proxy, hub, friends, presence, parties, inbox, time,
            NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);

        time.Advance(WatchPartyHostedService.CleanupInterval);

        Assert.Empty(inbox.Get(mario.Id).Entries);
        await service.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task APartyCleanupErrorDoesNotSkipTheNotifications()
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
        var inbox = TestInbox.Create(server, folder, time);
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        // La pulizia dei party lancia: l'elenco delle sessioni non risponde.
        var (sessions, sessionsStub) = InterfaceStub<ISessionDirectory>.Create();
        sessionsStub.Handlers["GetAppSessions"] = _ => throw new InvalidOperationException("sessioni non disponibili");
        var parties = new PartyService(
            directory, server, sessions, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        var mario = server.AddUser("Mario");
        await inbox.AnnounceAsync("vecchio");
        time.Advance(InboxService.MaxAge + TimeSpan.FromMinutes(1));
        var logger = new RecordingLogger<WatchPartyHostedService>();
        using var service = new WatchPartyHostedService(
            InterfaceStub<ISessionManager>.Create().Proxy, hub, friends, presence, parties, inbox, time, logger);
        await service.StartAsync(CancellationToken.None);

        time.Advance(WatchPartyHostedService.CleanupInterval);

        Assert.Empty(inbox.Get(mario.Id).Entries);
        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning && e.Message == "Pulizia dei watch party non riuscita");
        await service.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task ANotificationCleanupErrorIsLoggedOnItsOwn()
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
        // La pulizia delle notifiche lancia: la ricerca di un utente non risponde.
        var (users, usersStub) = InterfaceStub<IUserDirectory>.Create();
        usersStub.Handlers["GetUsers"] = _ => new[] { new UserRef(Guid.NewGuid(), "Mario", true, true) };
        usersStub.Handlers["GetUser"] = _ => throw new InvalidOperationException("utenti non disponibili");
        var inbox = new InboxService(
            new InboxStore(folder.InboxFile, NullLogger<InboxStore>.Instance),
            users, server, server, server, time, NullLogger<InboxService>.Instance);
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        var parties = new PartyService(
            directory, server, server, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        await inbox.AnnounceAsync("ciao");
        var logger = new RecordingLogger<WatchPartyHostedService>();
        using var service = new WatchPartyHostedService(
            InterfaceStub<ISessionManager>.Create().Proxy, hub, friends, presence, parties, inbox, time, logger);
        await service.StartAsync(CancellationToken.None);

        time.Advance(WatchPartyHostedService.CleanupInterval);

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Equal("Pulizia delle notifiche non riuscita", warning.Message);
        await service.StopAsync(CancellationToken.None);
    }
}
