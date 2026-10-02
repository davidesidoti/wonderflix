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
        using var service = new WatchPartyHostedService(manager, hub, time, NullLogger<WatchPartyHostedService>.Instance);
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
}
