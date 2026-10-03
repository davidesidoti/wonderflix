using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Regole dei party (spec F §6.4–6.8): registrazione con la modalità,
/// elenco filtrato, dettagli, codici, inviti, "in un party" per la lista
/// amici, pulizia e avvisi. Non conosce Jellyfin: parla con le interfacce
/// di Hub.
/// </summary>
public sealed class PartyService(
    PartyDirectory parties,
    IGroupDirectory groups,
    ISessionDirectory sessions,
    IUserDirectory users,
    FriendService friends,
    PartyRegistry registry,
    PartyAnnouncer announcer,
    IEventSender sender,
    RateLimiter limiter,
    InboxService inbox,
    ILogger<PartyService> logger)
{
    /// <summary>
    /// Registra il party appena creato da caller. L'avviso a chi lo deve
    /// sapere parte dopo, quando il gruppo ha la coda
    /// (<see cref="PartyAnnouncer"/>): la risposta non lo aspetta.
    /// </summary>
    public HubResult<RegisterPartyResponse> Register(CallerSession caller, Guid groupId, string? mode)
    {
        if (!PartyModes.IsValid(mode))
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Invalid);
        }

        // Solo chi ha appena creato il gruppo lo registra: l'app lo fa dentro
        // create, prima che qualcuno possa entrare. Un gruppo con altri
        // dentro (es. di jellyfin-web) non si può nascondere da fuori.
        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || group.Participants.Count != 1 || !IsParticipant(group, caller.UserName))
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Forbidden);
        }

        var view = parties.Register(groupId, caller.UserId, mode!);
        if (view is null)
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Conflict);
        }

        logger.LogDebug("Watch party {GroupId} registrato da {UserId}: {Mode}", groupId, caller.UserId, mode);
        announcer.Schedule(caller.SessionId, caller.UserId, groupId, mode!);
        return HubResult<RegisterPartyResponse>.Ok(new RegisterPartyResponse(view.Code));
    }

    /// <summary>I party che caller può vedere, dall'elenco SyncPlay della sua sessione.</summary>
    public IReadOnlyList<PartySummary> ListVisible(CallerSession caller)
    {
        var result = new List<PartySummary>();
        foreach (var group in groups.ListGroups(caller.SessionId))
        {
            parties.Seen(group.Id);
            if (!IsVisibleTo(group, caller.UserId, caller.UserName))
            {
                continue;
            }

            var mode = parties.Get(group.Id)?.Mode ?? PartyModes.Public;
            result.Add(new PartySummary(Id(group.Id), group.Name, group.State, group.Participants, mode));
        }

        return result;
    }

    /// <summary>Modalità e codice, per chi è nel gruppo.</summary>
    public HubResult<PartyDetails> GetDetails(CallerSession caller, Guid groupId)
    {
        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || !IsParticipant(group, caller.UserName))
        {
            return HubResult<PartyDetails>.Fail(HubStatus.Forbidden);
        }

        var view = parties.Get(groupId);
        return HubResult<PartyDetails>.Ok(new PartyDetails(view?.Mode ?? PartyModes.Public, view?.Code));
    }

    /// <summary>
    /// Il gruppo di un codice: chi lo usa diventa invitato (il party compare
    /// nel suo elenco). Ogni tentativo conta per il limite.
    /// </summary>
    public HubResult<JoinByCodeResponse> JoinByCode(CallerSession caller, string? code)
    {
        if (!limiter.TryAcquire(Id(caller.UserId), LimitTypes.CodeAttempts))
        {
            return HubResult<JoinByCodeResponse>.Fail(HubStatus.RateLimited);
        }

        var groupId = parties.FindByCode(code);
        // Un codice di un gruppo finito non vale più.
        if (groupId is null || groups.GetGroup(caller.SessionId, groupId.Value) is null)
        {
            return HubResult<JoinByCodeResponse>.Fail(HubStatus.Forbidden);
        }

        parties.Grant(groupId.Value, [caller.UserId]);
        return HubResult<JoinByCodeResponse>.Ok(new JoinByCodeResponse(Id(groupId.Value)));
    }

    /// <summary>
    /// Invita amici di caller che non sono nel party; gli altri id si saltano.
    /// Oltre il limite invita quelli che ci stanno e risponde RateLimited.
    /// L'avviso va solo alle sessioni degli invitati che vedono il gruppo:
    /// dalle altre (niente accesso alla libreria della coda) non si entra.
    /// Gli invitati che possono vedere il titolo trovano anche la voce nella
    /// cassetta delle notifiche (spec G §6.5).
    /// </summary>
    public async Task<HubStatus> InviteAsync(CallerSession caller, Guid groupId, IReadOnlyList<string>? userIds)
    {
        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || !IsParticipant(group, caller.UserName))
        {
            return HubStatus.Forbidden;
        }

        var targets = new List<Guid>();
        var limited = false;
        foreach (var raw in userIds ?? [])
        {
            if (!Guid.TryParse(raw, out var id) || targets.Contains(id))
            {
                continue;
            }

            var user = users.GetUser(id);
            if (user is null || !friends.AreFriends(caller.UserId, id) || IsParticipant(group, user.Name))
            {
                continue;
            }

            if (!limiter.TryAcquire(Id(caller.UserId), LimitTypes.Invites))
            {
                limited = true;
                break;
            }

            targets.Add(id);
        }

        parties.Grant(groupId, targets);
        logger.LogDebug("Inviti al watch party {GroupId} da {UserId}: {Count}", groupId, caller.UserId, targets.Count);
        var payload = JsonSerializer.Serialize(SocialEvent.PartyInvite(Id(groupId), group.Name, caller.UserName));
        var invitees = sessions.GetAppSessions()
            .Where(s => targets.Contains(s.UserId) && groups.GetGroup(s.SessionId, groupId) is not null)
            .Select(s => s.SessionId)
            .ToList();
        await Task.WhenAll(invitees.Select(sessionId => SendAsync(sessionId, payload))).ConfigureAwait(false);
        await inbox.AddInvitesAsync(caller, group, targets).ConfigureAwait(false);
        return limited ? HubStatus.RateLimited : HubStatus.Ok;
    }

    /// <summary>
    /// Il party in cui sta friendId (con l'app dentro il gruppo), se viewer
    /// può vederlo: per la modalità e, dalla sua sessione, per Jellyfin
    /// (accesso alla libreria della coda). null altrimenti (spec F §6.3).
    /// </summary>
    public FriendParty? PartyOf(CallerSession viewer, Guid friendId)
    {
        foreach (var session in sessions.GetAppSessions().Where(s => s.UserId == friendId))
        {
            var groupId = registry.GroupOf(session.SessionId);
            if (groupId is null)
            {
                continue;
            }

            var group = groups.GetGroup(session.SessionId, groupId.Value);
            // La voce del registro può essere vecchia (Leave non riuscita):
            // conta solo chi è ancora tra i partecipanti del gruppo.
            if (group is not null
                && IsParticipant(group, session.UserName)
                && IsVisibleTo(group, viewer.UserId, viewer.UserName)
                && groups.GetGroup(viewer.SessionId, group.Id) is not null)
            {
                return new FriendParty(Id(group.Id), PartyNames.TitleOf(group.Name));
            }
        }

        return null;
    }

    /// <summary>Toglie i party dei gruppi finiti; restituisce quanti.</summary>
    public int Cleanup()
    {
        var appSessions = sessions.GetAppSessions().Select(s => s.SessionId).ToList();
        return parties.Forget(groupId => appSessions.Any(sessionId => groups.GetGroup(sessionId, groupId) is not null));
    }

    private bool IsVisibleTo(GroupSummary group, Guid viewerId, string viewerName) =>
        IsParticipant(group, viewerName)
        || parties.IsVisible(group.Id, viewerId, creator => friends.AreFriends(creator, viewerId));

    private async Task SendAsync(string sessionId, string payload)
    {
        try
        {
            // Mai il token della richiesta: l'avviso non si ferma con lei.
            await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso del party non inviato alla sessione {SessionId}", sessionId);
        }
    }

    private static bool IsParticipant(GroupSummary group, string userName) =>
        group.Participants.Contains(userName, StringComparer.OrdinalIgnoreCase);

    private static string Id(Guid id) => id.ToString("N");
}
