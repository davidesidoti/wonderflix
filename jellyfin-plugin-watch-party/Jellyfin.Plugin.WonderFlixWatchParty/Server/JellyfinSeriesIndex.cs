using Jellyfin.Data.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Le serie di Jellyfin con gli id TVDB, TMDB e IMDb, per riconoscere quelle
/// di Sonarr (spec M §7.3). Una sola query senza utente: chi vede cosa lo
/// decide poi ILibraryAccess.CanSee, per ogni utente.
/// </summary>
public sealed class JellyfinSeriesIndex(ILibraryManager libraryManager) : ISeriesIndex
{
    public IReadOnlyList<LibrarySeries> GetSeries() =>
        libraryManager.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.Series],
                IsVirtualItem = false,
            })
            .Select(item => new LibrarySeries(
                item.Id,
                ProviderId(item, MetadataProvider.Tvdb),
                ProviderId(item, MetadataProvider.Tmdb),
                ProviderId(item, MetadataProvider.Imdb)))
            // Ordine stabile per id: con due serie uguali nessun utente passa dall'una all'altra fra una lettura e l'altra.
            .OrderBy(series => series.Id)
            .ToList();

    private static string? ProviderId(BaseItem item, MetadataProvider provider) =>
        item.TryGetProviderId(provider, out var value) && !string.IsNullOrWhiteSpace(value) ? value.Trim() : null;
}
