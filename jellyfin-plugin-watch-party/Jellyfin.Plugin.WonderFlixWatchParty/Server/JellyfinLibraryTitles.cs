using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin per il riepilogo dei nuovi titoli.</summary>
public sealed class JellyfinLibraryTitles(ILibraryManager libraryManager, IUserManager userManager) : ILibraryTitles
{
    public bool IsScanRunning => libraryManager.IsScanRunning;

    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public LibraryTitle? Get(Guid itemId)
    {
        if (itemId == Guid.Empty)
        {
            return null;
        }

        var item = libraryManager.GetItemById(itemId);
        if (!NewTitleRules.IsRealTitle(item))
        {
            return null;
        }

        var episode = item as Episode;
        var seriesKey = episode is null
            ? string.Empty
            : episode.SeriesPresentationUniqueKey ?? episode.FindSeriesPresentationUniqueKey() ?? string.Empty;

        // La serie dell'episodio, come Episode.Series ma dall'ILibraryManager
        // ricevuto; senza SeriesId l'episodio non si annuncia comunque.
        var series = episode is null || episode.SeriesId == Guid.Empty
            ? null
            : libraryManager.GetItemById(episode.SeriesId) as Series;
        return new LibraryTitle(
            item.Id,
            item is Movie,
            item.Name ?? string.Empty,
            item.ProductionYear,
            episode?.SeriesId ?? Guid.Empty,
            episode?.SeriesName ?? string.Empty,
            seriesKey,
            episode?.ParentIndexNumber,
            episode?.IndexNumber,
            NewTitleRules.ExternalKeys(item),
            item.DateLastRefreshed != DateTime.MinValue)
        {
            SeriesExternalKeys = series is null ? [] : NewTitleRules.ExternalKeys(series),
        };
    }

    // Conteggi sul database: i dati utente in memoria della serie possono
    // essere vecchi (Jellyfin li azzera sul genitore a ogni aggiunta). I
    // filtri per utente vogliono il costruttore con l'utente.
    // Senza utente: in Jellyfin 10.11 i filtri sull'utente (preferiti, visti,
    // iniziati, tag) entrano nella query solo se si chiedono; questi no.
    public bool HasOtherEpisodes(string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes)
    {
        if (string.IsNullOrEmpty(seriesKey))
        {
            return false;
        }

        return libraryManager.GetCount(new InternalItemsQuery
        {
            SeriesPresentationUniqueKey = seriesKey,
            IncludeItemTypes = [BaseItemKind.Episode],
            IsVirtualItem = false,
            ExcludeItemIds = excludeEpisodes.ToArray(),
        }) > 0;
    }

    public bool FollowsSeries(
        Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes, bool hasOtherEpisodes)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return false;
        }

        if (seriesId != Guid.Empty
            && libraryManager.GetCount(new InternalItemsQuery(user) { ItemIds = [seriesId], IsFavorite = true }) > 0)
        {
            return true;
        }

        // Senza altri episodi nessuno può averne visto o iniziato uno.
        if (!hasOtherEpisodes || string.IsNullOrEmpty(seriesKey))
        {
            return false;
        }

        return libraryManager.GetCount(OtherEpisodes(user, seriesKey, excludeEpisodes, played: true)) > 0
            || libraryManager.GetCount(OtherEpisodes(user, seriesKey, excludeEpisodes, played: false)) > 0;
    }

    /// <summary>Gli altri episodi veri della serie, visti (played) o iniziati.</summary>
    private static InternalItemsQuery OtherEpisodes(User user, string seriesKey, IReadOnlyCollection<Guid> exclude, bool played)
    {
        var query = new InternalItemsQuery(user)
        {
            SeriesPresentationUniqueKey = seriesKey,
            IncludeItemTypes = [BaseItemKind.Episode],
            IsVirtualItem = false,
            ExcludeItemIds = exclude.ToArray(),
        };
        if (played)
        {
            query.IsPlayed = true;
        }
        else
        {
            query.IsResumable = true;
        }

        return query;
    }
}
