using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin: elemento in riproduzione, visibilità e limiti sui contenuti per utente.</summary>
public sealed class JellyfinLibraryAccess(
    ISessionManager sessionManager,
    ILibraryManager libraryManager,
    IUserManager userManager) : ILibraryAccess
{
    public PlayingItem? NowPlaying(string sessionId)
    {
        var session = sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));
        if (session is null)
        {
            return null;
        }

        // Di solito c'è l'elemento intero; se no, quello del DTO.
        var item = session.FullNowPlayingItem;
        if (item is null && session.NowPlayingItem is { } dto && dto.Id != Guid.Empty)
        {
            item = libraryManager.GetItemById(dto.Id);
        }

        if (item is null)
        {
            return null;
        }

        var image = item is Episode episode && episode.SeriesId != Guid.Empty ? episode.SeriesId : item.Id;
        return new PlayingItem(item.Id, image);
    }

    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public bool CanSee(Guid userId, Guid itemId)
    {
        if (userId == Guid.Empty || itemId == Guid.Empty)
        {
            return false;
        }

        var user = userManager.GetUserById(userId);
        var item = libraryManager.GetItemById(itemId);
        return user is not null && item is not null && item.IsVisibleStandalone(user);
    }

    // I limiti del profilo che Jellyfin controlla in BaseItem.IsParentalAllowed.
    public bool HasContentLimits(Guid userId)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return true;
        }

        return user.MaxParentalRatingScore is not null
            || user.MaxParentalRatingSubScore is not null
            || HasPreference(user, PreferenceKind.BlockedTags)
            || HasPreference(user, PreferenceKind.AllowedTags)
            || HasPreference(user, PreferenceKind.BlockUnratedItems);
    }

    // La Dashboard può salvare una preferenza vuota: non è un limite.
    private static bool HasPreference(User user, PreferenceKind kind) =>
        user.GetPreference(kind).Any(value => !string.IsNullOrWhiteSpace(value));
}
