using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una lettura di Sonarr o Radarr: il valore, oppure un codice di <see cref="UpcomingErrors"/> (spec S §6.1).</summary>
public sealed record ArrRead<T>(T? Value, string? Error);

/// <summary>
/// Cache a chiavi delle letture di Sonarr e Radarr (spec S §6.1): come le slot
/// di <see cref="UpcomingService"/> ma per più chiavi. Una lettura in corso
/// vale sempre, una finita fino alla scadenza (<see cref="UpcomingService.CacheFor"/>,
/// o <see cref="UpcomingService.ErrorCacheFor"/> se in errore). Le chiavi le
/// compone chi chiama, con indirizzo e chiave del servizio dentro: restano solo in memoria.
/// </summary>
public sealed class ArrReadCache<T>(TimeProvider time, int maxEntries, ILogger logger)
{
    private readonly Lock _lock = new();
    private readonly Dictionary<string, Entry> _entries = [];

    // Ordine d'inserimento, per togliere la voce più vecchia.
    private readonly LinkedList<string> _order = new();

    /// <summary>La lettura in cache o una nuova, una sola anche con più chiamate insieme. Non lancia mai.</summary>
    public Task<ArrRead<T>> GetAsync(string key, Func<Task<T>> read)
    {
        lock (_lock)
        {
            if (_entries.TryGetValue(key, out var entry))
            {
                if (!entry.Read.IsCompleted || time.GetUtcNow() < entry.ExpiresAt)
                {
                    return entry.Read;
                }

                _entries.Remove(key);
                _order.Remove(key);
            }
            else if (_entries.Count >= maxEntries)
            {
                // Il limite vale per le voci finite: se sono tutte in corso, si aggiunge lo stesso.
                var oldest = _order.FirstOrDefault(k => _entries[k].Read.IsCompleted);
                if (oldest is not null)
                {
                    _entries.Remove(oldest);
                    _order.Remove(oldest);
                }
            }

            var fresh = new Entry();
            _entries[key] = fresh;
            _order.AddLast(key);

            // Su un altro thread e senza il token di chi chiede: la fine rientra in _lock per la scadenza.
            fresh.Read = Task.Run(() => ReadAndExpireAsync(fresh, read));
            return fresh.Read;
        }
    }

    private async Task<ArrRead<T>> ReadAndExpireAsync(Entry entry, Func<Task<T>> read)
    {
        ArrRead<T> result;
        try
        {
            result = new(await read().ConfigureAwait(false), null);
        }
        catch (ArrException ex)
        {
            result = new(default, UpcomingErrors.Code(ex.Error));
        }
        catch (Exception ex)
        {
            // Senza la chiave della cache: contiene la chiave API.
            logger.LogWarning(ex, "Lettura di Sonarr o Radarr non riuscita");
            result = new(default, UpcomingErrors.Unreachable);
        }

        lock (_lock)
        {
            entry.ExpiresAt = time.GetUtcNow() + (result.Error is null ? UpcomingService.CacheFor : UpcomingService.ErrorCacheFor);
        }

        return result;
    }

    private sealed class Entry
    {
        public Task<ArrRead<T>> Read { get; set; } = null!;

        public DateTimeOffset ExpiresAt { get; set; } = DateTimeOffset.MaxValue;
    }
}
