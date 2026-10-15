using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'azione del match: lo stato se riuscita, il motivo di un 409.</summary>
public sealed record MatchOutcome(HubStatus Status, string? Reason, MatchStateDto? State)
{
    public static readonly MatchOutcome RateLimited = new(HubStatus.RateLimited, null, null);

    public static MatchOutcome Ok(MatchStateDto? state = null) => new(HubStatus.Ok, null, state);

    public static MatchOutcome Conflict(string reason) => new(HubStatus.Conflict, reason, null);
}

/// <summary>
/// Le sale del match (spec P §6): in memoria, una per utente. Regole degli
/// endpoint, pescate della pila fuori dal lock, inviti, avvisi MatchUpdated
/// raggruppati e pulizia. Non conosce Jellyfin: parla con le interfacce di
/// Hub. Sicuro tra thread.
/// </summary>
#pragma warning disable CS9113 // parties serve a Party (Task 5)
public sealed class MatchService(
    MatchStackBuilder stacks,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    InboxService inbox,
    PartyDirectory parties,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<MatchService> logger) : IDisposable
#pragma warning restore CS9113
{
    /// <summary>Quanto un membro può restare senza sessioni WonderFlix (spec P §6.1).</summary>
    public static readonly TimeSpan MemberGrace = TimeSpan.FromSeconds(60);

    /// <summary>Senza voti né ingressi per tanto, la sala si chiude (spec P §6.1).</summary>
    public static readonly TimeSpan InactiveAfter = TimeSpan.FromHours(1);

    /// <summary>Quanto si tiene una sala chiusa, per chi si riconnette (spec P §6.1).</summary>
    public static readonly TimeSpan ClosedKept = TimeSpan.FromMinutes(5);

    /// <summary>Al più un MatchUpdated per sala ogni tanto (spec P §6.5).</summary>
    public static readonly TimeSpan PushInterval = TimeSpan.FromMilliseconds(250);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, MatchRoom> _rooms = [];
    private readonly Dictionary<Guid, PushState> _pushes = [];

    /// <summary>Apre una sala con chi chiama come unico membro.</summary>
    public MatchOutcome Open(Guid userId)
    {
        var name = users.GetUser(userId)?.Name ?? string.Empty;
        lock (_lock)
        {
            if (OpenRoomOf(userId) is not null)
            {
                return MatchOutcome.Conflict(MatchReasons.InAnotherRoom);
            }

            var room = new MatchRoom(Guid.NewGuid(), userId, name, time.GetUtcNow());
            _rooms[room.Id] = room;
            logger.LogDebug("Sala del match {RoomId} aperta da {UserId}", N(room.Id), N(userId));
            return MatchOutcome.Ok(room.Snapshot());
        }
    }

    /// <summary>Lo stato, per i membri (anche di una sala chiusa da poco).</summary>
    public MatchOutcome Get(Guid userId, Guid roomId)
    {
        lock (_lock)
        {
            return _rooms.TryGetValue(roomId, out var room) && room.IsMember(userId)
                ? MatchOutcome.Ok(room.Snapshot())
                : MatchOutcome.Conflict(MatchReasons.NotMember);
        }
    }

    /// <summary>
    /// Invita amici attivi di chi ha aperto la sala, in attesa (spec P §6.5);
    /// gli altri id si saltano. Oltre il limite invita quelli che ci stanno e
    /// risponde RateLimited. Avviso MatchInvite e voce nella cassetta.
    /// </summary>
    public async Task<MatchOutcome> InviteAsync(Guid userId, Guid roomId, IReadOnlyList<string>? userIds)
    {
        var targets = new List<Guid>();
        var limited = false;
        string fromName;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Waiting || room.Drawing)
            {
                return MatchOutcome.Conflict(MatchReasons.Started);
            }

            foreach (var raw in userIds ?? [])
            {
                if (!Guid.TryParse(raw, out var id) || targets.Contains(id) || room.IsMember(id))
                {
                    continue;
                }

                if (users.GetUser(id) is not { Enabled: true } || !friends.AreFriends(userId, id))
                {
                    continue;
                }

                if (!limiter.TryAcquire(N(userId), LimitTypes.Invites))
                {
                    limited = true;
                    break;
                }

                room.Invite(id);
                targets.Add(id);
            }

            fromName = room.CreatorName;
        }

        logger.LogDebug("Inviti alla sala del match {RoomId}: {Count}", N(roomId), targets.Count);
        var payload = JsonSerializer.Serialize(SocialEvent.MatchInvite(N(roomId), fromName));
        await SendAsync(targets, payload).ConfigureAwait(false);
        await inbox.AddMatchInvitesAsync(roomId, fromName, targets).ConfigureAwait(false);
        return limited ? MatchOutcome.RateLimited : MatchOutcome.Ok();
    }

    /// <summary>Entra un invitato, in attesa. Chi è già membro riceve lo stato.</summary>
    public MatchOutcome Join(Guid userId, Guid roomId)
    {
        var name = users.GetUser(userId)?.Name ?? string.Empty;
        Delivery? delivery;
        MatchStateDto state;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room))
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.IsOpen && !room.IsMember(userId) && OpenRoomOf(userId) is not null)
            {
                return MatchOutcome.Conflict(MatchReasons.InAnotherRoom);
            }

            var rev = room.Rev;
            if (room.Join(userId, name, time.GetUtcNow()) is { } reason)
            {
                return MatchOutcome.Conflict(reason);
            }

            delivery = room.Rev == rev ? null : Push(room, immediate: false);
            state = room.Snapshot();
        }

        Deliver(delivery);
        return MatchOutcome.Ok(state);
    }

    /// <summary>
    /// Esce chi chiama; se ha aperto la sala, la sala si chiude per tutti
    /// (spec P §6.1). Una sala sconosciuta o già chiusa non cambia.
    /// </summary>
    public void Leave(Guid userId, Guid roomId)
    {
        Delivery? delivery = null;
        lock (_lock)
        {
            if (_rooms.TryGetValue(roomId, out var room) && room.IsOpen && room.IsMember(userId))
            {
                if (userId == room.CreatorId)
                {
                    room.Close(MatchClosedReasons.CreatorLeft, null, time.GetUtcNow());
                    logger.LogDebug("Sala del match {RoomId} chiusa: {Reason}", N(roomId), MatchClosedReasons.CreatorLeft);
                }
                else
                {
                    room.Remove(userId);
                }

                delivery = Push(room, immediate: false);
            }
        }

        Deliver(delivery);
    }

    /// <summary>
    /// "Inizia" (spec P §6.2): solo chi ha aperto, in attesa, con almeno
    /// MinMembers membri. La pila si pesca fuori dal lock (piano 22a,
    /// decisione 3); se intanto la sala si chiude, la pescata si butta.
    /// </summary>
    public MatchOutcome Start(Guid userId, Guid roomId, MatchFilters filters)
    {
        IReadOnlyList<Guid> members;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Waiting || room.Drawing)
            {
                return MatchOutcome.Conflict(MatchReasons.Started);
            }

            if (room.MemberCount < MatchRoom.MinMembers)
            {
                return MatchOutcome.Conflict(MatchReasons.NotEnoughMembers);
            }

            room.Drawing = true;
            members = room.MemberIds;
        }

        var stack = stacks.Draw(userId, members, filters, []);

        Delivery? delivery;
        MatchStateDto state;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            room.Drawing = false;
            room.Start(filters, stack, time.GetUtcNow());
            delivery = Push(room, immediate: false);
            state = room.Snapshot();
        }

        Deliver(delivery);
        return MatchOutcome.Ok(state);
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var push in _pushes.Values)
            {
                push.Timer?.Dispose();
            }

            _pushes.Clear();
        }
    }

    // Solo sotto _lock. La sala aperta di cui l'utente è membro.
    private MatchRoom? OpenRoomOf(Guid userId) =>
        _rooms.Values.FirstOrDefault(room => room.IsOpen && room.IsMember(userId));

    // Solo sotto _lock. Spec P §6.5: il primo cambio dopo una pausa parte
    // subito; quelli dentro PushInterval aspettano il timer e partono con
    // l'ultimo stato. immediate manda subito (avvio del party).
    private Delivery? Push(MatchRoom room, bool immediate)
    {
        if (!_pushes.TryGetValue(room.Id, out var push))
        {
            push = new PushState();
            _pushes[room.Id] = push;
        }

        var now = time.GetUtcNow();
        if (immediate || (push.Timer is null && (push.LastAt is not { } last || now - last >= PushInterval)))
        {
            push.Timer?.Dispose();
            push.Timer = null;
            push.LastAt = now;
            return new Delivery(room.Snapshot(), room.MemberIds);
        }

        if (push.Timer is null)
        {
            var roomId = room.Id;
            push.Timer = time.CreateTimer(_ => FirePush(roomId), null, push.LastAt!.Value + PushInterval - now, Timeout.InfiniteTimeSpan);
        }

        return null;
    }

    private void FirePush(Guid roomId)
    {
        Delivery? delivery = null;
        lock (_lock)
        {
            if (_pushes.TryGetValue(roomId, out var push))
            {
                push.Timer?.Dispose();
                push.Timer = null;
                push.LastAt = time.GetUtcNow();
                if (_rooms.TryGetValue(roomId, out var room))
                {
                    delivery = new Delivery(room.Snapshot(), room.MemberIds);
                }
            }
        }

        Deliver(delivery);
    }

    // Fuori dal lock: le sessioni e gli invii passano da Jellyfin.
    private void Deliver(Delivery? delivery)
    {
        if (delivery is null)
        {
            return;
        }

        var payload = JsonSerializer.Serialize(SocialEvent.MatchUpdated(delivery.State));
        _ = SendAsync(delivery.UserIds, payload);
    }

    private async Task SendAsync(IReadOnlyCollection<Guid> userIds, string payload)
    {
        if (userIds.Count == 0)
        {
            return;
        }

        IReadOnlyList<string> targets;
        try
        {
            targets = sessions.GetAppSessions().Where(s => userIds.Contains(s.UserId)).Select(s => s.SessionId).ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Sessioni per gli avvisi del match non lette");
            return;
        }

        foreach (var sessionId in targets)
        {
            try
            {
                // Mai il token della richiesta: l'avviso non si ferma con lei.
                await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Avviso del match non inviato alla sessione {SessionId}", sessionId);
            }
        }
    }

    private static string N(Guid id) => id.ToString("N");

    private sealed record Delivery(MatchStateDto State, IReadOnlyList<Guid> UserIds);

    private sealed class PushState
    {
        public DateTimeOffset? LastAt { get; set; }

        public ITimer? Timer { get; set; }
    }
}
