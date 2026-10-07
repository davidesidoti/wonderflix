using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Le collezioni di Jellyfin (spec K §7.1): quelle della cartella delle
/// collezioni che l'utente vede, ognuna con i titoli collegati
/// (LinkedChildren) che l'utente può vedere. È la stessa chiamata che
/// Jellyfin fa per GET /Items?parentId=…: GetChildren(user, true, …)
/// filtra per librerie e controllo parentale.
/// </summary>
public sealed class JellyfinCollectionDirectory(
    ICollectionManager collectionManager,
    IUserManager userManager,
    IImageProcessor imageProcessor) : ICollectionDirectory
{
    public async Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId)
    {
        // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return [];
        }

        // Senza collezioni la cartella non c'è, e non va creata.
        var folder = await collectionManager.GetCollectionsFolder(false).ConfigureAwait(false);
        if (folder is null)
        {
            return [];
        }

        return folder.GetChildren(user, true, new InternalItemsQuery())
            .OfType<BoxSet>()
            .Select(boxSet => new CollectionInfo(
                boxSet.Id,
                boxSet.Name ?? string.Empty,
                boxSet.SortName ?? boxSet.Name ?? string.Empty,
                PrimaryTag(boxSet),
                boxSet.DateCreated,
                boxSet.GetChildren(user, true, new InternalItemsQuery()).Select(item => item.Id).ToList()))
            .ToList();
    }

    /// <summary>Il tag della locandina, come lo mette Jellyfin in ImageTags; null senza locandina.</summary>
    private string? PrimaryTag(BoxSet boxSet)
    {
        var image = boxSet.GetImageInfo(ImageType.Primary, 0);
        return image is null ? null : imageProcessor.GetImageCacheTag(boxSet, image);
    }
}
