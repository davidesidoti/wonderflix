using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>
/// Gli oggetti di Jellyfin (Folder e BoxSet) si simulano con sottoclassi che
/// restituiscono figli fissi e registrano chi li chiede: così si prova che i
/// figli si leggono sempre attraverso l'utente. La visibilità vera (librerie e
/// controllo parentale) si conferma sul server (piano 17a, Task 3 e Task 12).
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

    [Fact]
    public async Task ReadsCollectionsAndTheirTitlesThroughTheUser()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUserById"] = _ => mario;
        var (images, imageStub) = InterfaceStub<IImageProcessor>.Create();
        imageStub.Handlers["GetImageCacheTag"] = args => "tag-" + ((ItemImageInfo)args[1]!).Path;

        var childCalls = new List<(User User, bool IncludeLinkedChildren)>();
        var created = new DateTime(2026, 5, 1, 10, 0, 0, DateTimeKind.Utc);
        var matrixId = Guid.NewGuid();
        var noNameId = Guid.NewGuid();
        var titles = new[] { Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid() };
        // SortName sempre esplicito: il getter pigro legge la configurazione statica del server.
        var matrix = new FakeBoxSet(childCalls, [new Movie { Id = titles[0] }, new Movie { Id = titles[1] }])
        {
            Id = matrixId,
            Name = "Matrix - Collezione",
            SortName = "matrix - collezione",
            DateCreated = created,
            ImageInfos = [new ItemImageInfo { Type = ImageType.Primary, Path = "matrix.jpg" }],
        };
        var noName = new FakeBoxSet(childCalls, [new Movie { Id = titles[2] }])
        {
            Id = noNameId,
            Name = null!,
            SortName = null!,
            DateCreated = created,
        };
        var folder = new FakeFolder(childCalls, [matrix, noName, new Movie { Id = Guid.NewGuid() }]);
        var (collections, collectionStub) = InterfaceStub<ICollectionManager>.Create();
        collectionStub.Handlers["GetCollectionsFolder"] = _ => Task.FromResult<Folder?>(folder);

        var found = await new JellyfinCollectionDirectory(collections, users, images).GetCollectionsAsync(mario.Id);

        // Il film sciolto nella cartella non è una collezione.
        Assert.Equal(2, found.Count);
        Assert.Equal(matrixId, found[0].Id);
        Assert.Equal("Matrix - Collezione", found[0].Name);
        Assert.Equal("matrix - collezione", found[0].SortName);
        Assert.Equal("tag-matrix.jpg", found[0].PrimaryImageTag);
        Assert.Equal(created, found[0].DateCreated);
        Assert.Equal(new[] { titles[0], titles[1] }, found[0].ItemIds);
        Assert.Equal(noNameId, found[1].Id);
        Assert.Equal(string.Empty, found[1].Name);
        Assert.Equal(string.Empty, found[1].SortName);
        Assert.Null(found[1].PrimaryImageTag);
        Assert.Equal(created, found[1].DateCreated);
        Assert.Equal(new[] { titles[2] }, found[1].ItemIds);

        // La cartella e ogni collezione: sempre attraverso l'utente, con i collegati.
        Assert.Equal(3, childCalls.Count);
        Assert.All(childCalls, call =>
        {
            Assert.Same(mario, call.User);
            Assert.True(call.IncludeLinkedChildren);
        });
    }

    private sealed class FakeFolder(List<(User User, bool IncludeLinkedChildren)> calls, IReadOnlyList<BaseItem> children)
        : Folder
    {
        public override IReadOnlyList<BaseItem> GetChildren(User user, bool includeLinkedChildren, InternalItemsQuery query)
        {
            calls.Add((user, includeLinkedChildren));
            return children;
        }
    }

    private sealed class FakeBoxSet(List<(User User, bool IncludeLinkedChildren)> calls, IReadOnlyList<BaseItem> children)
        : BoxSet
    {
        public override IReadOnlyList<BaseItem> GetChildren(User user, bool includeLinkedChildren, InternalItemsQuery query)
        {
            calls.Add((user, includeLinkedChildren));
            return children;
        }
    }
}
