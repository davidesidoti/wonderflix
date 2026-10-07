using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>
/// Solo i casi senza utente o senza cartella: le collezioni vere (BoxSet e i
/// loro figli collegati) hanno bisogno del server, e si provano lì (piano
/// 17a, Task 3 e Task 12).
/// </summary>
public class CollectionDirectoryTests
{
    [Fact]
    public async Task WithoutTheUserOrTheFolderThereAreNoCollections()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        // Come UserManager vero: con un id vuoto lancia.
        userStub.Handlers["GetUserById"] = args => (Guid)args[0]! == Guid.Empty
            ? throw new ArgumentException("userId vuoto")
            : (Guid)args[0]! == mario.Id ? mario : null;
        var (collections, collectionStub) = InterfaceStub<ICollectionManager>.Create();
        collectionStub.Handlers["GetCollectionsFolder"] = _ => Task.FromResult<Folder?>(null);
        var directory = new JellyfinCollectionDirectory(
            collections, users, InterfaceStub<IImageProcessor>.Create().Proxy);

        Assert.Empty(await directory.GetCollectionsAsync(Guid.Empty));
        Assert.Empty(await directory.GetCollectionsAsync(Guid.NewGuid()));
        Assert.DoesNotContain(collectionStub.Calls, c => c.Name == "GetCollectionsFolder");
        Assert.DoesNotContain(userStub.Calls, c => c.Name == "GetUserById" && (Guid)c.Args[0]! == Guid.Empty);

        Assert.Empty(await directory.GetCollectionsAsync(mario.Id));
        var folderCall = Assert.Single(collectionStub.Calls, c => c.Name == "GetCollectionsFolder");
        // Mai creare la cartella: senza collezioni non serve.
        Assert.False((bool)folderCall.Args[0]!);
    }
}
