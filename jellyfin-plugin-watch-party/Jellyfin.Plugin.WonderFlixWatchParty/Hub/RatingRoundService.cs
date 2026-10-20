using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'azione della votazione: lo stato se riuscita ({} se State è null), il motivo di un 409.</summary>
public sealed record RatingOutcome(HubStatus Status, string? Reason, RatingRoundDto? State)
{
    public static readonly RatingOutcome Invalid = new(HubStatus.Invalid, null, null);

    public static readonly RatingOutcome RateLimited = new(HubStatus.RateLimited, null, null);

    public static RatingOutcome Ok(RatingRoundDto? state) => new(HubStatus.Ok, null, state);

    public static RatingOutcome Conflict(string reason) => new(HubStatus.Conflict, reason, null);
}

/// <summary>
/// Le votazioni di fine party (spec Q §6.2): una per gruppo, in memoria. Presenti
/// da SyncPlay, regole degli endpoint, timer dei 2 minuti, avvisi
/// RatingRoundUpdated raggruppati (uno per destinatario, con il suo stato) e
/// pulizia. Non conosce Jellyfin. Sicuro tra thread; ordine dei lock: questo,
/// poi quello di RatingService (che non chiama mai le votazioni).
/// </summary>
public sealed class RatingRoundService(
    RatingService ratings,
    IRatingLibrary library,
    ILibraryAccess access,
    IGroupDirectory groups,
    ISessionDirectory sessions,
    IUserDirectory users,
    PartyDirectory parties,
    IEventSender sender,
    TimeProvider time,
    ILogger<RatingRoundService> logger) : IDisposable
{
    /// <summary>Dopo tanto dall'apertura i voti si scoprono comunque (spec Q §6.2).</summary>
    public static readonly TimeSpan VotingTime = TimeSpan.FromMinutes(2);

    /// <summary>Quanto si tiene una votazione scoperta, per chi arriva tardi.</summary>
    public static readonly TimeSpan RevealedKept = TimeSpan.FromMinutes(10);

    /// <summary>Al più un avviso per votazione ogni tanto.</summary>
    public static readonly TimeSpan PushInterval = TimeSpan.FromMilliseconds(250);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, RatingRound> _rounds = [];
    private readonly Dictionary<Guid, ITimer> _timers = [];
    private readonly Dictionary<Guid, PushState> _pushes = [];

    /// <summary>Apre la votazione del gruppo sul titolo di <paramref name="request"/>; la stessa si restituisce com'è.</summary>
    public RatingOutcome Open(Guid userId, OpenRatingRoundRequest? request)
    {
        if (request is null || !TryId(request.GroupId, out var groupId) || !TryId(request.ItemId, out var itemId))
        {
            return RatingOutcome.Invalid;
        }

        var present = Present(groupId, userId, Known(groupId));
        if (present is null || present.All(u => u.Id != userId))
        {
            return RatingOutcome.Conflict(RatingReasons.NotMember);
        }

        Guid target;
        try
        {
            if (!access.CanSee(userId, itemId) || library.RoundTarget(itemId) is not { } resolved
                || library.FindRated(resolved) is null)
            {
                return RatingOutcome.Invalid;
            }

            target = resolved;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Libreria non disponibile per la votazione {GroupId}", N(groupId));
            return RatingOutcome.Invalid;
        }

        Delivery? delivery;
        RatingRoundDto state;
        lock (_lock)
        {
            var rev = 0L;
            if (_rounds.TryGetValue(groupId, out var round) && round.ItemId == target)
            {
                rev = round.Rev;
            }
            else
            {
                if (round is not null)
                {
                    logger.LogDebug("Votazione {GroupId} chiusa: nuovo titolo {ItemId}", N(groupId), N(target));
                    DisposeTimer(groupId);
                }

                round = new RatingRound(groupId, target, time.GetUtcNow(), VotingTime);
                _rounds[groupId] = round;
                var opened = round;
                _timers[groupId] = time.CreateTimer(_ => Expire(groupId, opened), null, VotingTime, Timeout.InfiniteTimeSpan);
                logger.LogDebug("Votazione {GroupId} aperta su {ItemId}", N(groupId), N(target));
            }

            round.SetPresent(present);
            RevealIfDue(round);
            delivery = round.Rev == rev ? null : Push(round);
            state = Snapshot(round, userId);
        }

        Deliver(delivery);
        return RatingOutcome.Ok(state);
    }

    /// <summary>Lo stato per un presente; {} (State null) senza votazione o per chi non è presente.</summary>
    public RatingOutcome Get(Guid userId, Guid groupId) => Act(userId, groupId, isGet: true, _ => null);

    /// <summary>Il voto di un presente: si scrive nell'archivio e si segna Voted. Ammesso anche dopo la scoperta.</summary>
    public RatingOutcome Vote(Guid userId, Guid groupId, RateRequest? request) =>
        Act(userId, groupId, isGet: false, round =>
        {
            var status = ratings.Save(userId, round.ItemId, request?.Score, request?.Comment);
            if (status != HubStatus.Ok)
            {
                return status == HubStatus.RateLimited ? RatingOutcome.RateLimited : RatingOutcome.Invalid;
            }

            round.Vote(userId);
            return null;
        });

    /// <summary>"Non voto": Closed una volta scoperti i voti.</summary>
    public RatingOutcome Skip(Guid userId, Guid groupId) =>
        Act(userId, groupId, isGet: false, round => round.Skip(userId) ? null : RatingOutcome.Conflict(RatingReasons.Closed));

    /// <summary>Scopre i voti: solo il creatore del party. Se sono già scoperti non cambia nulla.</summary>
    public RatingOutcome Reveal(Guid userId, Guid groupId) =>
        Act(userId, groupId, isGet: false, round =>
        {
            if (parties.Get(groupId)?.CreatorId != userId)
            {
                return RatingOutcome.Conflict(RatingReasons.NotCreator);
            }

            if (round.Reveal(time.GetUtcNow()))
            {
                logger.LogDebug("Votazione {GroupId}: voti scoperti (creator)", N(groupId));
            }

            return null;
        });

    /// <summary>
    /// Scarta le votazioni di un gruppo finito o scoperte da RevealedKept; alle altre
    /// aggiorna presenti e fase. Nessun avviso per le scartate. Restituisce quanti cambi.
    /// </summary>
    public int Cleanup()
    {
        List<(Guid GroupId, Guid[] Known)> all;
        lock (_lock)
        {
            all = _rounds.Select(r => (r.Key, r.Value.PresentIds.ToArray())).ToList();
        }

        var changes = 0;
        foreach (var (groupId, known) in all)
        {
            var present = Present(groupId, Guid.Empty, known);
            Delivery? delivery = null;
            lock (_lock)
            {
                if (!_rounds.TryGetValue(groupId, out var round))
                {
                    continue;
                }

                if (present is null)
                {
                    Discard(groupId, "gruppo finito");
                    changes++;
                    continue;
                }

                if (round.RevealedAt is { } revealedAt && time.GetUtcNow() - revealedAt >= RevealedKept)
                {
                    Discard(groupId, "tempo finito");
                    changes++;
                    continue;
                }

                var rev = round.Rev;
                round.SetPresent(present);
                RevealIfDue(round);
                if (round.Rev != rev)
                {
                    changes++;
                    delivery = Push(round);
                }
            }

            Deliver(delivery);
        }

        return changes;
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var timer in _timers.Values)
            {
                timer.Dispose();
            }

            foreach (var push in _pushes.Values)
            {
                push.Timer?.Dispose();
            }

            _timers.Clear();
            _pushes.Clear();
        }
    }

    // Ogni chiamata su una votazione: presenti riletti fuori dal lock, poi SetPresent e
    // RevealIfDue, poi l'azione (null = riuscita) e lo stato per chi chiama.
    private RatingOutcome Act(Guid userId, Guid groupId, bool isGet, Func<RatingRound, RatingOutcome?> action)
    {
        var missing = isGet ? RatingOutcome.Ok(null) : RatingOutcome.Conflict(RatingReasons.Closed);
        var known = Known(groupId);
        if (known is null)
        {
            return missing;
        }

        var present = Present(groupId, userId, known);
        Delivery? delivery;
        RatingOutcome result;
        lock (_lock)
        {
            if (!_rounds.TryGetValue(groupId, out var round))
            {
                return missing;
            }

            var rev = round.Rev;
            if (present is not null)
            {
                round.SetPresent(present);
            }

            if (present is null || present.All(u => u.Id != userId))
            {
                result = isGet ? RatingOutcome.Ok(null) : RatingOutcome.Conflict(RatingReasons.NotMember);
            }
            else
            {
                RevealIfDue(round);
                result = action(round) ?? RatingOutcome.Ok(null);
                RevealIfDue(round);
                if (result.Status == HubStatus.Ok)
                {
                    result = RatingOutcome.Ok(Snapshot(round, userId));
                }
            }

            delivery = round.Rev == rev ? null : Push(round);
        }

        Deliver(delivery);
        return result;
    }

    // Il timer dei 2 minuti: scopre i voti senza altre chiamate. Gira su un thread del
    // pool: un errore (es. l'archivio illeggibile) non deve uscire e fermare Jellyfin.
    private void Expire(Guid groupId, RatingRound round)
    {
        Delivery? delivery = null;
        try
        {
            lock (_lock)
            {
                // Reveal diretto: un tick appena prima di EndsAt non deve lasciare la votazione in Voting.
                if (_rounds.TryGetValue(groupId, out var current) && current == round && round.Reveal(time.GetUtcNow()))
                {
                    logger.LogDebug("Votazione {GroupId}: voti scoperti (timeout)", N(groupId));
                    delivery = Push(round);
                }
            }

            Deliver(delivery);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Timer della votazione {GroupId} fallito", N(groupId));
        }
    }

    // I presenti noti della votazione, o null se non c'è.
    private Guid[]? Known(Guid groupId)
    {
        lock (_lock)
        {
            return _rounds.TryGetValue(groupId, out var round) ? [.. round.PresentIds] : null;
        }
    }

    // Fuori dal lock (chiede a Jellyfin): le sessioni di chi chiama, poi quelle dei già
    // presenti; vale la prima risposta non null. I nomi di SyncPlay diventano utenti
    // senza badare alle maiuscole; chi non si trova si salta.
    private IReadOnlyList<UserRef>? Present(Guid groupId, Guid callerId, IEnumerable<Guid>? known)
    {
        var all = sessions.GetAppSessions();
        foreach (var userId in new[] { callerId }.Concat(known ?? []).Distinct())
        {
            foreach (var session in all.Where(s => s.UserId == userId))
            {
                if (groups.GetParticipants(session.SessionId, groupId) is not { } names)
                {
                    continue;
                }

                var byName = users.GetUsers()
                    .GroupBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                    .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
                return names.Select(n => byName.GetValueOrDefault(n)).OfType<UserRef>().DistinctBy(u => u.Id).ToList();
            }
        }

        return null;
    }

    // Solo sotto _lock.
    private void RevealIfDue(RatingRound round)
    {
        if (round.RevealIfDue(time.GetUtcNow()) is { } reason)
        {
            logger.LogDebug("Votazione {GroupId}: voti scoperti ({Reason})", N(round.GroupId), reason);
        }
    }

    // Solo sotto _lock.
    private void Discard(Guid groupId, string reason)
    {
        _rounds.Remove(groupId);
        DisposeTimer(groupId);
        if (_pushes.Remove(groupId, out var push))
        {
            push.Timer?.Dispose();
        }

        logger.LogDebug("Votazione {GroupId} scartata: {Reason}", N(groupId), reason);
    }

    private void DisposeTimer(Guid groupId)
    {
        if (_timers.Remove(groupId, out var timer))
        {
            timer.Dispose();
        }
    }

    // Solo sotto _lock. Il voto di chi guarda sta nell'archivio (decisione 3).
    private RatingRoundDto Snapshot(RatingRound round, Guid viewerId) =>
        round.Snapshot(viewerId, parties.Get(round.GroupId)?.CreatorId == viewerId, ratings.Of(round.ItemId, round.PresentIds));

    // Solo sotto _lock: uno stato per presente.
    private Delivery Build(RatingRound round)
    {
        var creator = parties.Get(round.GroupId)?.CreatorId;
        var ids = round.PresentIds.ToList();
        var votes = ratings.Of(round.ItemId, ids);
        return new Delivery([.. ids.Select(id => (id, round.Snapshot(id, id == creator, votes)))]);
    }

    // Solo sotto _lock, come MatchService: il primo cambio dopo una pausa parte
    // subito; quelli dentro PushInterval aspettano il timer e partono con l'ultimo stato.
    private Delivery? Push(RatingRound round)
    {
        if (!_pushes.TryGetValue(round.GroupId, out var push))
        {
            push = new PushState();
            _pushes[round.GroupId] = push;
        }

        var now = time.GetUtcNow();
        if (push.Timer is null && (push.LastAt is not { } last || now - last >= PushInterval))
        {
            push.LastAt = now;
            return Build(round);
        }

        if (push.Timer is null)
        {
            var groupId = round.GroupId;
            push.Timer = time.CreateTimer(_ => FirePush(groupId), null, push.LastAt!.Value + PushInterval - now, Timeout.InfiniteTimeSpan);
        }

        return null;
    }

    private void FirePush(Guid groupId)
    {
        try
        {
            Delivery? delivery = null;
            lock (_lock)
            {
                if (_pushes.TryGetValue(groupId, out var push))
                {
                    push.Timer?.Dispose();
                    push.Timer = null;
                    push.LastAt = time.GetUtcNow();
                    if (_rounds.TryGetValue(groupId, out var round))
                    {
                        delivery = Build(round);
                    }
                }
            }

            Deliver(delivery);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Avviso della votazione {GroupId} fallito", N(groupId));
        }
    }

    // Fuori dal lock: le sessioni e gli invii passano da Jellyfin.
    private void Deliver(Delivery? delivery)
    {
        if (delivery is not null)
        {
            _ = SendAsync(delivery);
        }
    }

    private async Task SendAsync(Delivery delivery)
    {
        IReadOnlyList<CallerSession> app;
        try
        {
            app = sessions.GetAppSessions();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Sessioni per gli avvisi della votazione non lette");
            return;
        }

        foreach (var (userId, state) in delivery.States)
        {
            var payload = JsonSerializer.Serialize(SocialEvent.RatingRoundUpdated(state));
            foreach (var session in app.Where(s => s.UserId == userId))
            {
                try
                {
                    // Mai il token della richiesta: l'avviso non si ferma con lei.
                    await sender.TrySendAsync(session.SessionId, payload, CancellationToken.None).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogWarning(ex, "Avviso della votazione non inviato alla sessione {SessionId}", session.SessionId);
                }
            }
        }
    }

    private static bool TryId(string? raw, out Guid id) => Guid.TryParse(raw, out id) && id != Guid.Empty;

    private static string N(Guid id) => id.ToString("N");

    private sealed record Delivery(IReadOnlyList<(Guid UserId, RatingRoundDto State)> States);

    private sealed class PushState
    {
        public DateTimeOffset? LastAt { get; set; }

        public ITimer? Timer { get; set; }
    }
}
