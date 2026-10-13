using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le riproduzioni delle sessioni WonderFlix di Jellyfin (spec O §6.2, §6.5).</summary>
public sealed class JellyfinPlaybackDirectory(ISessionManager sessionManager, ILibraryManager libraryManager) : IPlaybackDirectory
{
    public IReadOnlyList<AppPlayback> GetAppPlayback()
    {
        var list = new List<AppPlayback>();
        foreach (var session in sessionManager.Sessions)
        {
            if (!string.Equals(session.Client, WatchPartyProtocol.ClientName, StringComparison.Ordinal)
                || session.UserId.Equals(Guid.Empty)
                || PlayingTitles.From(ItemOf(session)) is not { } title)
            {
                continue;
            }

            // Jellyfin fa avanzare PositionTicks da sé ogni secondo (piano 21a, decisione 4);
            // LastPlaybackCheckIn è in UTC, a volte senza dirlo.
            list.Add(new AppPlayback(
                session.Id,
                session.UserId,
                title,
                session.PlayState?.PositionTicks ?? 0,
                new DateTimeOffset(DateTime.SpecifyKind(session.LastPlaybackCheckIn, DateTimeKind.Utc))));
        }

        return list;
    }

    // Di solito c'è l'elemento intero; se no, quello del DTO (come JellyfinLibraryAccess.NowPlaying).
    private BaseItem? ItemOf(SessionInfo session) =>
        session.FullNowPlayingItem
        ?? (session.NowPlayingItem is { } dto && dto.Id != Guid.Empty ? libraryManager.GetItemById(dto.Id) : null);
}
