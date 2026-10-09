using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti di frequenza per chiave e tipo, a finestra scorrevole (spec E
/// §6.6, spec F §6.9, spec L §7.5). La chiave è la sessione per gli eventi
/// del canale, l'utente per gli amici e i contatti, il nome scritto per il
/// recupero. Sicuro tra thread.
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
            [LimitTypes.RecoveryStartMinute] = (1, TimeSpan.FromMinutes(1)),
            [LimitTypes.RecoveryStartHour] = (5, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryStartDay] = (10, TimeSpan.FromHours(24)),
            [LimitTypes.RecoveryStartGlobal] = (30, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryFail] = (10, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryFailDay] = (20, TimeSpan.FromHours(24)),
            [LimitTypes.RecoveryFailGlobal] = (100, TimeSpan.FromHours(24)),
            [LimitTypes.LinkStartMinute] = (1, TimeSpan.FromMinutes(1)),
            [LimitTypes.LinkStartHour] = (5, TimeSpan.FromHours(1)),
            [LimitTypes.PasswordChecks] = (10, TimeSpan.FromHours(1)),
        };

    /// <summary>
    /// Con tante chiavi in memoria, prima di crearne una nuova si tolgono
    /// quelle ormai fuori finestra. Le chiavi anonime del recupero (i nomi
    /// scritti) non hanno un Forget: senza questo resterebbero per sempre.
    /// </summary>
    internal const int SweepThreshold = 1024;

    private readonly Lock _lock = new();
    private readonly Dictionary<(string SessionId, string Type), Queue<DateTimeOffset>> _sent = [];

    /// <summary>Chiavi in memoria (per i test).</summary>
    internal int Count
    {
        get
        {
            lock (_lock)
            {
                return _sent.Count;
            }
        }
    }

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
                if (_sent.Count >= SweepThreshold)
                {
                    Sweep(now);
                }

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

    /// <summary>true se la chiave ha già finito quelli di questo tipo adesso; non conta niente.</summary>
    public bool IsLimited(string key, string type)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return false;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            return _sent.TryGetValue((key, type), out var times)
                && times.Count(t => now - t < limit.Window) >= limit.Count;
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

    // Solo sotto _lock. Toglie le chiavi senza nessun invio dentro la finestra
    // del loro tipo: contare non cambierebbe niente. I tipi sconosciuti non
    // entrano mai in _sent (TryAcquire esce prima).
    private void Sweep(DateTimeOffset now)
    {
        var stale = _sent
            .Where(entry => !entry.Value.Any(t => now - t < Limits[entry.Key.Type].Window))
            .Select(entry => entry.Key)
            .ToList();
        foreach (var key in stale)
        {
            _sent.Remove(key);
        }
    }
}
