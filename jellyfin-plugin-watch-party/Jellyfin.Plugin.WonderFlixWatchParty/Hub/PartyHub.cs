using System.Globalization;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'operazione di <see cref="PartyHub"/>.</summary>
public enum HubStatus
{
    /// <summary>Riuscita.</summary>
    Ok,

    /// <summary>Gruppo inesistente o utente non nel gruppo (403).</summary>
    Forbidden,

    /// <summary>Evento non valido (400).</summary>
    Invalid,

    /// <summary>Limite di frequenza superato (429).</summary>
    RateLimited,
}

/// <summary>Esito con il valore, se riuscita.</summary>
public sealed record HubResult<T>(HubStatus Status, T? Value)
    where T : class
{
    public static HubResult<T> Ok(T value) => new(HubStatus.Ok, value);

    public static HubResult<T> Fail(HubStatus status) => new(status, null);
}

/// <summary>
/// Il centro del plugin (spec E §6): registro dei gruppi, storico della chat,
/// limiti e inoltro. Non conosce Jellyfin: parla con le interfacce di Hub.
/// </summary>
public sealed class PartyHub(
    IGroupDirectory groups,
    ISessionDirectory sessions,
    IEventSender sender,
    PartyRegistry registry,
    ChatHistory history,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<PartyHub> logger)
{
    /// <summary>Registra la sessione nel gruppo e restituisce lo storico della chat.</summary>
    public HubResult<IReadOnlyList<StampedEvent>> Join(CallerSession caller, Guid groupId)
    {
        if (ParticipantsFor(caller, groupId) is null)
        {
            return HubResult<IReadOnlyList<StampedEvent>>.Fail(HubStatus.Forbidden);
        }

        registry.Register(groupId, caller.SessionId, caller.UserName);
        logger.LogDebug("Sessione {SessionId} nel watch party {GroupId}", caller.SessionId, groupId);
        return HubResult<IReadOnlyList<StampedEvent>>.Ok(history.Get(groupId));
    }

    public void Leave(CallerSession caller, Guid groupId) =>
        registry.Unregister(groupId, caller.SessionId);

    /// <summary>
    /// Valida, timbra, conserva (solo la chat) e inoltra un evento agli altri
    /// membri. Registra anche chi lo manda, se non lo era (es. dopo un
    /// riavvio del plugin).
    /// </summary>
    public async Task<HubResult<StampedEvent>> PostAsync(
        CallerSession caller,
        Guid groupId,
        EventRequest? request,
        CancellationToken cancellationToken)
    {
        var valid = EventValidator.Validate(request);
        if (valid is null)
        {
            return HubResult<StampedEvent>.Fail(HubStatus.Invalid);
        }

        var participants = ParticipantsFor(caller, groupId);
        if (participants is null)
        {
            return HubResult<StampedEvent>.Fail(HubStatus.Forbidden);
        }

        if (!limiter.TryAcquire(caller.SessionId, valid.Type))
        {
            return HubResult<StampedEvent>.Fail(HubStatus.RateLimited);
        }

        registry.Register(groupId, caller.SessionId, caller.UserName);
        var stamped = new StampedEvent
        {
            Id = Guid.NewGuid().ToString("N"),
            GroupId = groupId.ToString("N"),
            Type = valid.Type,
            UserId = caller.UserId.ToString("N"),
            UserName = caller.UserName,
            SentAt = time.GetUtcNow().UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
            Action = valid.Action,
            PositionTicks = valid.PositionTicks,
            Text = valid.Text,
            Reaction = valid.Reaction,
        };
        if (valid.Type == EventTypes.Chat)
        {
            history.Add(groupId, stamped);
        }

        // Mai il testo nei log (spec E §6.6).
        logger.LogDebug("Evento {Type} di {UserId} nel watch party {GroupId}", valid.Type, caller.UserId, groupId);
        // Il token di chi manda non va oltre qui: l'inoltro agli altri non si ferma con la sua richiesta.
        await ForwardAsync(groupId, caller.SessionId, participants, stamped).ConfigureAwait(false);
        return HubResult<StampedEvent>.Ok(stamped);
    }

    /// <summary>Una sessione è finita (evento SessionEnded di Jellyfin).</summary>
    public void RemoveSession(string sessionId)
    {
        registry.RemoveSession(sessionId);
        limiter.Forget(sessionId);
    }

    /// <summary>
    /// Toglie registro e storico dei gruppi finiti o senza sessioni vive
    /// (spec E §6.5). Restituisce quanti gruppi ha tolto.
    /// </summary>
    public int Cleanup()
    {
        var removed = 0;
        foreach (var groupId in registry.GetGroups().Concat(history.GetGroups()).Distinct().ToList())
        {
            var alive = registry.GetSessions(groupId).Any(s =>
                sessions.Exists(s.SessionId) && groups.GetParticipants(s.SessionId, groupId) is not null);
            if (alive)
            {
                continue;
            }

            registry.RemoveGroup(groupId);
            history.Remove(groupId);
            removed++;
        }

        return removed;
    }

    /// <summary>
    /// I partecipanti del gruppo se chi chiama ne fa parte (confronto dei
    /// nomi senza maiuscole, spec E §6.4); altrimenti null.
    /// </summary>
    private IReadOnlyList<string>? ParticipantsFor(CallerSession caller, Guid groupId)
    {
        var participants = groups.GetParticipants(caller.SessionId, groupId);
        return participants is not null && participants.Contains(caller.UserName, StringComparer.OrdinalIgnoreCase)
            ? participants
            : null;
    }

    /// <summary>
    /// Inoltra alle sessioni registrate del gruppo, tranne chi ha mandato
    /// l'evento; toglie dal registro le sessioni finite e quelle il cui
    /// utente non è più tra i partecipanti.
    /// </summary>
    private async Task ForwardAsync(
        Guid groupId,
        string senderSessionId,
        IReadOnlyList<string> participants,
        StampedEvent stamped)
    {
        var payload = JsonSerializer.Serialize(stamped);
        var targets = new List<string>();
        foreach (var (sessionId, userName) in registry.GetSessions(groupId))
        {
            if (sessionId == senderSessionId)
            {
                continue;
            }

            if (!sessions.Exists(sessionId) || !participants.Contains(userName, StringComparer.OrdinalIgnoreCase))
            {
                registry.Unregister(groupId, sessionId);
                continue;
            }

            targets.Add(sessionId);
        }

        await Task.WhenAll(targets.Select(sessionId => SendAsync(groupId, sessionId, payload)))
            .ConfigureAwait(false);
    }

    private async Task SendAsync(Guid groupId, string sessionId, string payload)
    {
        try
        {
            // Mai il token della richiesta di chi manda: se si interrompe a metà
            // invio, .NET può chiudere il WebSocket di chi riceve.
            if (!await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false))
            {
                registry.Unregister(groupId, sessionId);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Evento del watch party non inoltrato alla sessione {SessionId}", sessionId);
        }
    }
}
