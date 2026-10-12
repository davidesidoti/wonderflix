using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin per i consigli: film e serie, e l'ultima visione di un utente.</summary>
public sealed class JellyfinRecommendationLibrary(
    ILibraryManager libraryManager,
    IUserManager userManager,
    IUserDataManager userDataManager) : IRecommendationLibrary
{
    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public RecommendableItem? GetTitle(Guid itemId) =>
        itemId != Guid.Empty && libraryManager.GetItemById(itemId) is { } item && item is Movie or Series
            ? new RecommendableItem(item.Id, item.Name ?? string.Empty, item.ProductionYear)
            : null;

    public DateTimeOffset? LastWatched(Guid userId, Guid itemId)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        var item = itemId == Guid.Empty ? null : libraryManager.GetItemById(itemId);
        if (user is null || item is null)
        {
            return null;
        }

        if (item is Series)
        {
            // Una domanda sola al database (piano 20a, decisione 7): l'episodio
            // vero della serie visto per ultimo da questo utente. DatePlayed
            // ordina per LastPlayedDate dell'utente della query; gli episodi
            // mai visti (null) vanno in fondo.
            item = libraryManager.GetItemList(new InternalItemsQuery(user)
            {
                AncestorIds = [item.Id],
                IncludeItemTypes = [BaseItemKind.Episode],
                IsVirtualItem = false,
                OrderBy = [(ItemSortBy.DatePlayed, SortOrder.Descending)],
                Limit = 1,
            }).FirstOrDefault();
            if (item is null)
            {
                return null;
            }
        }

        // Jellyfin salva le date in UTC, a volte senza dirlo (Kind Unspecified).
        var played = userDataManager.GetUserData(user, item)?.LastPlayedDate;
        return played is { } date ? new DateTimeOffset(DateTime.SpecifyKind(date, DateTimeKind.Utc)) : null;
    }
}
