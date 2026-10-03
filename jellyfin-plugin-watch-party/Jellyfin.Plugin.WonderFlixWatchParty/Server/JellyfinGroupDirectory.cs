using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Controller.SyncPlay.Requests;
using MediaBrowser.Model.SyncPlay;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager) : IGroupDirectory
{
    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        GetGroup(sessionId, groupId)?.Participants;

    public IReadOnlyList<GroupSummary> ListGroups(string sessionId)
    {
        var session = Find(sessionId);
        return session is null
            ? []
            : syncPlayManager.ListGroups(session, new ListGroupsRequest()).Select(ToSummary).ToList();
    }

    public GroupSummary? GetGroup(string sessionId, Guid groupId)
    {
        var session = Find(sessionId);
        // GetGroup restituisce null se il gruppo non esiste o l'utente non
        // può vederne la coda.
        return session is not null && syncPlayManager.GetGroup(session, groupId) is { } group
            ? ToSummary(group)
            : null;
    }

    private SessionInfo? Find(string sessionId) =>
        sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));

    private static GroupSummary ToSummary(GroupInfoDto group) =>
        new(group.GroupId, group.GroupName, group.State.ToString(), group.Participants);
}
