using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Controller.SyncPlay.Requests;
using MediaBrowser.Model.SyncPlay;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager,
    ILogger<JellyfinGroupDirectory> logger) : IGroupDirectory
{
    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        GetGroup(sessionId, groupId)?.Participants;

    // Jellyfin 10.11.9: Group.HasAccessToQueue chiama IsVisibleStandalone
    // sugli elementi in coda, anche su quelli che non esistono più, e
    // ListGroups/GetGroup vanno in NullReferenceException. Un errore di
    // SyncPlay qui non deve diventare un 500 di Friends o Parties: si
    // risponde "nessun gruppo" e si scrive nel log.
    public IReadOnlyList<GroupSummary> ListGroups(string sessionId)
    {
        var session = Find(sessionId);
        if (session is null)
        {
            return [];
        }

        try
        {
            return syncPlayManager.ListGroups(session, new ListGroupsRequest()).Select(ToSummary).ToList();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Elenco dei gruppi SyncPlay non riuscito");
            return [];
        }
    }

    public GroupSummary? GetGroup(string sessionId, Guid groupId)
    {
        var session = Find(sessionId);
        if (session is null)
        {
            return null;
        }

        try
        {
            // GetGroup restituisce null se il gruppo non esiste o l'utente non
            // può vederne la coda.
            return syncPlayManager.GetGroup(session, groupId) is { } group ? ToSummary(group) : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Gruppo SyncPlay {GroupId} non letto", groupId);
            return null;
        }
    }

    private SessionInfo? Find(string sessionId) =>
        sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));

    private static GroupSummary ToSummary(GroupInfoDto group) =>
        new(group.GroupId, group.GroupName, group.State.ToString(), group.Participants);
}
