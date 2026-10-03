using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private InboxStore Store() => new(_folder.InboxFile, NullLogger<InboxStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().List(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.InboxFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var mario = Guid.NewGuid();
        var book = new InboxBook();
        book.Add(mario, new InboxEntry { Type = InboxEntryTypes.Announcement, CreatedAt = Now, Text = "ciao" });

        Store().Save(book);

        Assert.True(File.Exists(_folder.InboxFile));
        Assert.False(File.Exists(_folder.InboxFile + ".tmp"));
        var entry = Assert.Single(Store().Load().List(mario));
        Assert.Equal("ciao", entry.Text);
        Assert.Equal(Now, entry.CreatedAt);
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.InboxFile)!);
        File.WriteAllText(_folder.InboxFile, "{ non è json");

        Assert.Empty(Store().Load().List(Guid.NewGuid()));

        Assert.False(File.Exists(_folder.InboxFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.InboxFile + ".bad"));
    }

    [Fact]
    public void NullEntriesAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.InboxFile)!);
        File.WriteAllText(
            _folder.InboxFile,
            "{\"Version\":1,\"Users\":{\"" + Guid.NewGuid().ToString("N") + "\":{\"NextSeq\":1,\"Entries\":[null]}}}");

        Store().Load();

        Assert.True(File.Exists(_folder.InboxFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsNextToTheFriends()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "inbox.json"),
            InboxStore.DefaultPath(paths));
    }
}
