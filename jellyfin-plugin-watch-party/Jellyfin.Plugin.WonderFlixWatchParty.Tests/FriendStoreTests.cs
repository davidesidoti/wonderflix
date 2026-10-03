using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class FriendStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private FriendStore Store() => new(_folder.FriendsFile, NullLogger<FriendStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        var graph = Store().Load();
        Assert.Empty(graph.FriendsOf(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.FriendsFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var graph = new FriendGraph();
        graph.Request(mario, luigi, Now);
        graph.Accept(luigi, mario);

        Store().Save(graph);

        Assert.True(File.Exists(_folder.FriendsFile));
        Assert.False(File.Exists(_folder.FriendsFile + ".tmp"));
        Assert.True(Store().Load().AreFriends(mario, luigi));
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.FriendsFile)!);
        File.WriteAllText(_folder.FriendsFile, "{ non è json");

        var graph = Store().Load();

        Assert.Empty(graph.FriendsOf(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.FriendsFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.FriendsFile + ".bad"));
    }

    [Fact]
    public void BadIdsAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.FriendsFile)!);
        File.WriteAllText(_folder.FriendsFile, "{\"Version\":1,\"Friendships\":[[\"x\",\"y\"]],\"Requests\":[]}");

        Store().Load();

        Assert.True(File.Exists(_folder.FriendsFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsInThePluginConfigurations()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "friends.json"),
            FriendStore.DefaultPath(paths));
    }
}
