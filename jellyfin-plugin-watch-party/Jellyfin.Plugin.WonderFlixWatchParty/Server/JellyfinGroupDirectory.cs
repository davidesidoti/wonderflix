using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager) : IGroupDirectory
{
    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId)
    {
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.Id, sessionId, StringComparison.Ordinal));
        // GetGroup restituisce null se il gruppo non esiste o l'utente non
        // può vederne la coda.
        return session is null ? null : syncPlayManager.GetGroup(session, groupId)?.Participants;
    }
}
