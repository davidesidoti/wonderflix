using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti di frequenza per chiave e tipo, a finestra scorrevole (spec E
/// §6.6, spec F §6.9). La chiave è la sessione per gli eventi del canale,
/// l'utente per gli amici. Sicuro tra thread.
/// </summary>
public sealed class RateLimiter(TimeProvider time)
{
    private static readonly Dictionary<string, (int Count, TimeSpan Window)> Limits =
        new(StringComparer.Ordinal)
        {
            [EventTypes.Chat] = (5, TimeSpan.FromSeconds(10)),
            [EventTypes.Reaction] = (8, TimeSpan.FromSeconds(5)),
            [EventTypes.Action] = (20, TimeSpan.FromSeconds(10)),
            [LimitTypes.FriendRequests] = (20, TimeSpan.FromHours(1)),
            [LimitTypes.Searches] = (30, TimeSpan.FromMinutes(1)),
            [LimitTypes.CodeAttempts] = (5, TimeSpan.FromMinutes(1)),
            [LimitTypes.Invites] = (20, TimeSpan.FromMinutes(1)),
        };

    private readonly Lock _lock = new();
    private readonly Dictionary<(string SessionId, string Type), Queue<DateTimeOffset>> _sent = [];

    /// <summary>true (e si conta) se la chiave può farne un altro di questo tipo adesso.</summary>
    public bool TryAcquire(string key, string type)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return true;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_sent.TryGetValue((key, type), out var times))
            {
                times = new Queue<DateTimeOffset>();
                _sent[(key, type)] = times;
            }

            while (times.Count > 0 && now - times.Peek() >= limit.Window)
            {
                times.Dequeue();
            }

            if (times.Count >= limit.Count)
            {
                return false;
            }

            times.Enqueue(now);
            return true;
        }
    }

    /// <summary>La sessione è finita: i suoi conteggi non servono più.</summary>
    public void Forget(string sessionId)
    {
        lock (_lock)
        {
            foreach (var key in _sent.Keys.Where(k => k.SessionId == sessionId).ToList())
            {
                _sent.Remove(key);
            }
        }
    }
}
