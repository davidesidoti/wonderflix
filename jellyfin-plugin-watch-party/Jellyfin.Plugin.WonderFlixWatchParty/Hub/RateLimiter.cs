using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti di frequenza per sessione e tipo di evento, a finestra scorrevole
/// (spec E §6.6). Sicuro tra thread.
/// </summary>
public sealed class RateLimiter(TimeProvider time)
{
    private static readonly Dictionary<string, (int Count, TimeSpan Window)> Limits =
        new(StringComparer.Ordinal)
        {
            [EventTypes.Chat] = (5, TimeSpan.FromSeconds(10)),
            [EventTypes.Reaction] = (8, TimeSpan.FromSeconds(5)),
            [EventTypes.Action] = (20, TimeSpan.FromSeconds(10)),
        };

    private readonly Lock _lock = new();
    private readonly Dictionary<(string SessionId, string Type), Queue<DateTimeOffset>> _sent = [];

    /// <summary>true (e l'evento si conta) se la sessione può mandarne un altro di questo tipo adesso.</summary>
    public bool TryAcquire(string sessionId, string type)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return true;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_sent.TryGetValue((sessionId, type), out var times))
            {
                times = new Queue<DateTimeOffset>();
                _sent[(sessionId, type)] = times;
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
