using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityStoreTests : IDisposable
{
    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private ActivityStore Store() => new(_folder.ActivityFile, NullLogger<ActivityStore>.Instance);

    [Fact]
    public void AMissingFileIsAnEmptyBook()
    {
        var book = Store().Load();

        Assert.Empty(book.Views(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.ActivityFile));
    }

    [Fact]
    public void SavedViewsAndChoicesComeBack()
    {
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var dune = Guid.NewGuid();
        var at = new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero);
        var book = new ActivityBook();
        book.Record(mario, dune, at);
        book.SetShare(luigi, false);

        Store().Save(book);
        var loaded = Store().Load();

        Assert.Equal(new[] { new WatchedTitle(dune, at) }, loaded.Views(mario));
        Assert.False(loaded.Shares(luigi));
        Assert.False(File.Exists(_folder.ActivityFile + ".tmp"));
    }

    [Fact]
    public void AnUnreadableFileMovesToBadAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ActivityFile)!);
        File.WriteAllText(_folder.ActivityFile, "{ rotto");

        var book = Store().Load();

        Assert.Empty(book.Views(Guid.NewGuid()));
        Assert.True(File.Exists(_folder.ActivityFile + ".bad"));
        Assert.False(File.Exists(_folder.ActivityFile));
    }

    [Fact]
    public void AnUnreadableFileThatCannotMoveStillStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ActivityFile)!);
        File.WriteAllText(_folder.ActivityFile, "{\"Hidden\":[\"x\"]}");

        // Una cartella al posto di activity.json.bad: File.Move(..., overwrite: true) fallisce.
        Directory.CreateDirectory(_folder.ActivityFile + ".bad");

        var book = Store().Load();

        Assert.True(book.Shares(Guid.NewGuid()));
    }

    [Fact]
    public void TheDefaultPathIsNextToTheInbox()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");

        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "activity.json"),
            ActivityStore.DefaultPath(paths));
    }
}
