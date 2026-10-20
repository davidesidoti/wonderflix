using System.Globalization;
using Jellyfin.Data.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Le domande dei voti a Jellyfin (spec Q §12). Verificato sul sorgente di 10.11.9 (firme anche a 10.11.0):
/// - IsPlayed con IncludeItemTypes = [Episode] guarda la riga dati dell'utente della query (serve new InternalItemsQuery(user)); senza riga vale "non visto".
/// - IsVirtualItem ?? IsMissing: IsVirtualItem = false toglie gli episodi mancanti.
/// - Gli episodi di una stagione si scelgono per ParentIndexNumber (Series.FilterEpisodesBySeason), non per cartella.
/// - Episode.IndexNumberEnd copre i doppi (E05-E06): "dopo" è MinIndexNumber = (IndexNumberEnd ?? IndexNumber) + 1.
/// - Played lo mette UserDataManager.UpdatePlayState a fine riproduzione (oltre MaxResumePct o a 1 s dalla fine).
/// </summary>
public sealed class JellyfinRatingLibrary(
    ILibraryManager libraryManager,
    IUserManager userManager,
    IUserDataManager userDataManager) : IRatingLibrary
{
    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public RatedTitle? FindRated(Guid itemId)
    {
        if (itemId == Guid.Empty)
        {
            return null;
        }

        switch (libraryManager.GetItemById(itemId))
        {
            case Movie movie:
                var name = movie.Name ?? string.Empty;
                return new RatedTitle(movie.Id, false, movie.ProductionYear is { } year
                    ? string.Create(CultureInfo.InvariantCulture, $"{name} ({year})")
                    : name);
            case Season { IndexNumber: { } number } season:
                var series = season.SeriesName ?? string.Empty;
                return new RatedTitle(season.Id, true, number == 0
                    ? $"{series} · Speciali"
                    : string.Create(CultureInfo.InvariantCulture, $"{series} · Stagione {number}"));
            default:
                return null;
        }
    }

    public Guid? RoundTarget(Guid itemId)
    {
        if (itemId == Guid.Empty)
        {
            return null;
        }

        switch (libraryManager.GetItemById(itemId))
        {
            case Movie movie:
                return movie.Id;
            case Episode { SeasonId: var seasonId, SeriesId: var seriesId, ParentIndexNumber: { } seasonNumber, IndexNumber: { } number } episode
                when seasonId != Guid.Empty && seriesId != Guid.Empty:
                var after = libraryManager.GetItemList(new InternalItemsQuery
                {
                    AncestorIds = [seriesId],
                    IncludeItemTypes = [BaseItemKind.Episode],
                    ParentIndexNumber = seasonNumber,
                    MinIndexNumber = (episode.IndexNumberEnd ?? number) + 1,
                    IsVirtualItem = false,
                    Limit = 1,
                });
                return after.Count == 0 ? seasonId : null;
            default:
                return null;
        }
    }

    public bool HasWatched(Guid userId, RatedTitle title)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return false;
        }

        switch (libraryManager.GetItemById(title.Id))
        {
            case Movie movie:
                return userDataManager.GetUserData(user, movie)?.Played == true;
            case Season { IndexNumber: { } number, SeriesId: var seriesId }:
                // Il costruttore con l'utente porta i suoi limiti d'età e la sua riga "visto".
                return libraryManager.GetItemList(new InternalItemsQuery(user)
                {
                    AncestorIds = [seriesId],
                    IncludeItemTypes = [BaseItemKind.Episode],
                    ParentIndexNumber = number,
                    IsVirtualItem = false,
                    IsPlayed = false,
                    Limit = 1,
                }).Count == 0;
            default:
                return false;
        }
    }
}
