using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Avvisa che un party è partito (PartyStarted, spec F §6.8). L'app
/// registra il gruppo appena creato, prima di mandare la coda, e un gruppo
/// senza coda lo vede chiunque (Jellyfin controlla l'accesso alla libreria
/// sugli elementi in coda). L'avviso parte quindi solo quando il gruppo ha
/// la coda, e solo alle sessioni che in quel momento lo vedono. Si controlla
/// ogni <see cref="Delay"/>; dopo <see cref="GiveUpAfter"/> senza coda si
/// lascia perdere. Gli invii non bloccano nessuno. Sicuro tra thread.
/// </summary>
public sealed class PartyAnnouncer(
    PartyDirectory parties,
    IGroupDirectory groups,
    ISessionDirectory sessions,
    FriendService friends,
    IEventSender sender,
    TimeProvider time,
    ILogger<PartyAnnouncer> logger) : IDisposable
{
    /// <summary>
    /// Attesa tra la registrazione e il primo controllo, e tra un controllo
    /// e l'altro finché il gruppo non ha la coda (come
    /// <see cref="PresenceTracker.Delay"/>).
    /// </summary>
    public static readonly TimeSpan Delay = TimeSpan.FromSeconds(2);

    /// <summary>
    /// Dopo quanto dalla registrazione, con il gruppo ancora senza coda,
    /// l'avviso si lascia perdere (l'app manda la coda subito dopo la
    /// registrazione).
    /// </summary>
    public static readonly TimeSpan GiveUpAfter = TimeSpan.FromSeconds(20);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Pending> _pending = [];

    /// <summary>
    /// Prepara l'avviso del party groupId, appena registrato da
    /// creatorUserId dalla sessione creatorSessionId. I privati non si
    /// annunciano.
    /// </summary>
    public void Schedule(string creatorSessionId, Guid creatorUserId, Guid groupId, string mode)
    {
        if (mode is not (PartyModes.Public or PartyModes.Friends))
        {
            return;
        }

        var pending = new Pending(creatorSessionId, creatorUserId, groupId, mode, time.GetUtcNow());
        lock (_lock)
        {
            // Un party si registra una volta sola: un secondo avviso non serve.
            if (_pending.TryAdd(groupId, pending))
            {
                Arm(pending);
            }
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var pending in _pending.Values)
            {
                pending.Timer?.Dispose();
            }

            _pending.Clear();
        }
    }

    // Solo sotto _lock.
    private void Arm(Pending pending)
    {
        pending.Timer?.Dispose();
        pending.Timer = time.CreateTimer(_ => Tick(pending), null, Delay, Timeout.InfiniteTimeSpan);
    }

    private void Tick(Pending pending)
    {
        lock (_lock)
        {
            // Dispose è passato di qui.
            if (!_pending.TryGetValue(pending.GroupId, out var current) || !ReferenceEquals(current, pending))
            {
                return;
            }
        }

        try
        {
            // Fuori dal lock: si chiede a Jellyfin.
            var group = groups.GetGroup(pending.CreatorSessionId, pending.GroupId);
            if (group is null || parties.Get(pending.GroupId) is null)
            {
                logger.LogDebug("Watch party {GroupId} finito prima dell'avviso", pending.GroupId);
                Close(pending);
                return;
            }

            if (group.State == GroupStateNames.Idle)
            {
                if (time.GetUtcNow() - pending.ScheduledAt >= GiveUpAfter)
                {
                    logger.LogDebug("Watch party {GroupId} ancora senza coda: nessun avviso", pending.GroupId);
                    Close(pending);
                }
                else
                {
                    Rearm(pending);
                }

                return;
            }

            Close(pending);
            var targets = Audience(pending);
            logger.LogDebug("Watch party {GroupId} annunciato a {Count} sessioni", pending.GroupId, targets.Count);
            var payload = JsonSerializer.Serialize(SocialEvent.PartyStarted(Id(group.Id), group.Name, pending.Mode));
            _ = Task.WhenAll(targets.Select(sessionId => SendAsync(sessionId, payload)));
        }
        catch (Exception ex)
        {
            // Un'eccezione nel callback di un timer fermerebbe il server.
            logger.LogWarning(ex, "Avviso del watch party {GroupId} non riuscito", pending.GroupId);
            Close(pending);
        }
    }

    /// <summary>
    /// Le sessioni da avvisare, adesso: pubblico → le app degli altri,
    /// amici → le app degli amici di oggi del creatore. Solo le sessioni che
    /// vedono il gruppo (ora che ha la coda, Jellyfin controlla la libreria)
    /// e i cui utenti non ci sono già dentro.
    /// </summary>
    private List<string> Audience(Pending pending)
    {
        var candidates = sessions.GetAppSessions().Where(s => s.UserId != pending.CreatorUserId);
        if (pending.Mode == PartyModes.Friends)
        {
            var friendIds = friends.FriendsOf(pending.CreatorUserId).ToHashSet();
            candidates = candidates.Where(s => friendIds.Contains(s.UserId));
        }

        return candidates
            .Where(s => groups.GetGroup(s.SessionId, pending.GroupId) is { } seen
                && !seen.Participants.Contains(s.UserName, StringComparer.OrdinalIgnoreCase))
            .Select(s => s.SessionId)
            .ToList();
    }

    private void Rearm(Pending pending)
    {
        lock (_lock)
        {
            if (_pending.TryGetValue(pending.GroupId, out var current) && ReferenceEquals(current, pending))
            {
                Arm(pending);
            }
        }
    }

    private void Close(Pending pending)
    {
        lock (_lock)
        {
            if (_pending.TryGetValue(pending.GroupId, out var current) && ReferenceEquals(current, pending))
            {
                _pending.Remove(pending.GroupId);
                pending.Timer?.Dispose();
            }
        }
    }

    private async Task SendAsync(string sessionId, string payload)
    {
        try
        {
            // Nessuna richiesta da seguire: l'invio non si ferma.
            await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso del party non inviato alla sessione {SessionId}", sessionId);
        }
    }

    private static string Id(Guid id) => id.ToString("N");

    /// <summary>Un avviso in attesa.</summary>
    private sealed class Pending(string creatorSessionId, Guid creatorUserId, Guid groupId, string mode, DateTimeOffset scheduledAt)
    {
        public string CreatorSessionId { get; } = creatorSessionId;

        public Guid CreatorUserId { get; } = creatorUserId;

        public Guid GroupId { get; } = groupId;

        public string Mode { get; } = mode;

        public DateTimeOffset ScheduledAt { get; } = scheduledAt;

        /// <summary>Il timer del prossimo controllo; solo sotto _lock.</summary>
        public ITimer? Timer { get; set; }
    }
}
