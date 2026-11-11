using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Film e serie di Jellyfin con i trailer e l'id TMDB, solo per chi li può vedere.</summary>
public sealed class JellyfinTrailerLibrary(ILibraryManager libraryManager, ILibraryAccess access) : ITrailerLibrary
{
    public TrailerItem? Find(Guid userId, Guid itemId)
    {
        if (!access.CanSee(userId, itemId))
        {
            return null;
        }

        var item = libraryManager.GetItemById(itemId);
        var mediaType = item switch
        {
            Movie => RequestMediaTypes.Movie,
            Series => RequestMediaTypes.Tv,
            _ => null,
        };
        if (item is null || mediaType is null)
        {
            return null;
        }

        int? tmdb = item.TryGetProviderId(MetadataProvider.Tmdb, out var value) && int.TryParse(value, out var id) && id > 0
            ? id
            : null;
        var urls = item.RemoteTrailers.Select(t => t.Url).Where(u => !string.IsNullOrWhiteSpace(u)).ToList();
        return new TrailerItem(mediaType, tmdb, urls);
    }
}
