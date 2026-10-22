using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyRegistryTests
{
    private static readonly Guid G1 = Guid.Parse("11111111111111111111111111111111");
    private static readonly Guid G2 = Guid.Parse("22222222222222222222222222222222");

    private static IEnumerable<string> Names(PartyRegistry registry, Guid group) =>
        registry.GetSessions(group).Select(s => $"{s.SessionId}:{s.UserName}").Order();

    [Fact]
    public void RegisterAndList()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G1, "s2", "Luigi");
        Assert.Equal(new[] { "s1:Mario", "s2:Luigi" }, Names(registry, G1));
        Assert.True(registry.IsRegistered(G1, "s2"));
        Assert.Empty(registry.GetSessions(G2));
    }

    [Fact]
    public void ASessionIsInOneGroupOnly()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G2, "s1", "Mario");
        Assert.False(registry.IsRegistered(G1, "s1"));
        Assert.True(registry.IsRegistered(G2, "s1"));
        Assert.Equal(G2, Assert.Single(registry.GetGroups()));
    }

    [Fact]
    public void UnregisterRemoveSessionAndRemoveGroup()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G1, "s2", "Luigi");
        registry.Unregister(G1, "s1");
        Assert.False(registry.IsRegistered(G1, "s1"));
        registry.RemoveSession("s2");
        Assert.Empty(registry.GetGroups());
        registry.Register(G1, "s3", "Peach");
        registry.RemoveGroup(G1);
        Assert.Empty(registry.GetSessions(G1));
    }

    [Fact]
    public void GroupOfASession()
    {
        var registry = new PartyRegistry();
        var group = Guid.NewGuid();
        registry.Register(group, "s1", "Mario");
        Assert.Equal(group, registry.GroupOf("s1"));
        Assert.Null(registry.GroupOf("s2"));
        registry.Unregister(group, "s1");
        Assert.Null(registry.GroupOf("s1"));
    }
}
