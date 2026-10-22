using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La query a caso del match su Jellyfin (spec P §6.2): film e serie della
/// libreria che l'utente vede, del genere scelto, mai visti da lui, in
/// ordine casuale. Una query per tipo: con film e serie insieme Jellyfin
/// guarderebbe "visto" sulla riga della serie, che non vale (piano 22a, Task 7).
/// </summary>
public sealed class JellyfinMatchLibrary(ILibraryManager libraryManager, IUserManager userManager) : IMatchLibrary
{
    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public IReadOnlyList<MatchCandidate> Candidates(
        Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return [];
        }

        BaseItemKind[] kinds = (filters.Movies, filters.Series) switch
        {
            (true, true) => [BaseItemKind.Movie, BaseItemKind.Series],
            (true, false) => [BaseItemKind.Movie],
            (false, true) => [BaseItemKind.Series],
            _ => [],
        };
        var candidates = new List<MatchCandidate>();
        foreach (var kind in kinds)
        {
            // Il costruttore con l'utente porta i suoi limiti d'età e i tag
            // bloccati; GetItemList aggiunge le sue librerie e ricontrolla
            // IsVisible, quindi i risultati possono essere meno di Limit.
            var query = new InternalItemsQuery(user)
            {
                IncludeItemTypes = [kind],
                Recursive = true,
                IsVirtualItem = false,
                IsPlayed = false,
                ExcludeItemIds = [.. exclude],
                OrderBy = [(ItemSortBy.Random, SortOrder.Ascending)],
                Limit = limit / kinds.Length,
                // Il massimo dei "brutti" lo controlla la pila: Jellyfin non ce l'ha.
                MinCommunityRating = filters.MinRating,
            };
            if (filters.Genre is { } genre)
            {
                query.Genres = [genre];
            }

            candidates.AddRange(libraryManager.GetItemList(query)
                .Select(item => new MatchCandidate(item.Id, item is Movie, item.RunTimeTicks, item.CommunityRating)));
        }

        // Ognuna delle due liste è già a caso: si mescolano tra loro.
        var shuffled = candidates.ToArray();
        Random.Shared.Shuffle(shuffled);
        return shuffled;
    }
}
