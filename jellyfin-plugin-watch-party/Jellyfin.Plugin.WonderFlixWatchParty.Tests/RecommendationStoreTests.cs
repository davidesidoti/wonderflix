using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 12, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private RecommendationStore Store() => new(_folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().List(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.RecommendationsFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var (luigi, dune, mario) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var book = new RecommendationBook();
        book.Add(luigi, dune, mario, "da vedere", Now);

        Store().Save(book);

        Assert.True(File.Exists(_folder.RecommendationsFile));
        Assert.False(File.Exists(_folder.RecommendationsFile + ".tmp"));
        var sender = Assert.Single(Assert.Single(Store().Load().List(luigi)).From);
        Assert.Equal(mario, sender.UserId);
        Assert.Equal("da vedere", sender.Message);
        Assert.Equal(Now, sender.CreatedAt);
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(_folder.RecommendationsFile, "{ non è json");

        Assert.Empty(Store().Load().List(Guid.NewGuid()));

        Assert.False(File.Exists(_folder.RecommendationsFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.RecommendationsFile + ".bad"));
    }

    [Fact]
    public void FailedMoveAsideStillStartsEmptyAndTheNextSaveOverwrites()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(_folder.RecommendationsFile, "{ non è json");

        // Una cartella al posto di recommendations.json.bad: File.Move(..., overwrite: true) fallisce.
        Directory.CreateDirectory(_folder.RecommendationsFile + ".bad");

        var store = Store();
        var book = store.Load();
        Assert.Empty(book.List(Guid.NewGuid()));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.RecommendationsFile));

        var (luigi, dune, mario) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        book.Add(luigi, dune, mario, null, Now);
        store.Save(book);

        Assert.Single(Store().Load().List(luigi));
    }

    [Fact]
    public void BrokenEntriesAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(
            _folder.RecommendationsFile,
            "{\"Version\":1,\"Users\":{\"" + Guid.NewGuid().ToString("N") + "\":[{\"ItemId\":\"x\",\"From\":[]}]}}");

        Store().Load();

        Assert.True(File.Exists(_folder.RecommendationsFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsNextToTheInbox()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "recommendations.json"),
            RecommendationStore.DefaultPath(paths));
    }
}
