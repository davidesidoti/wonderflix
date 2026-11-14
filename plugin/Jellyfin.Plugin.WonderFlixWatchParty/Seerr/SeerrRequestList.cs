namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// L'elenco grezzo delle richieste di Seerr (tutte, filtro "all", nell'ordine di Seerr),
/// letto pagina per pagina e ricordato per <see cref="CacheFor"/> per ambito
/// (<c>requestedBy</c>, null = tutte). Chiamate insieme sullo stesso ambito condividono
/// una sola lettura; una lettura fallita non si ricorda. Sicuro tra thread.
/// </summary>
public sealed class SeerrRequestList(ISeerrClient seerr, TimeProvider time)
{
    /// <summary>Quanto vale un elenco letto.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(30);

    /// <summary>Richieste chieste a Seerr per pagina.</summary>
    public const int PageSize = 100;

    // Chiave -1 = tutte le richieste (requestedBy null).
    private readonly Dictionary<int, (Task<IReadOnlyList<SeerrRequest>> Read, DateTimeOffset At)> _cache = [];
    private readonly object _lock = new();

    /// <summary>Le richieste dell'ambito; <paramref name="requestedBy"/> null = di tutti.</summary>
    public Task<IReadOnlyList<SeerrRequest>> GetAsync(int asUser, int? requestedBy, CancellationToken ct)
    {
        Task<IReadOnlyList<SeerrRequest>> read;
        var key = requestedBy ?? -1;
        lock (_lock)
        {
            if (_cache.TryGetValue(key, out var hit) && time.GetUtcNow() - hit.At < CacheFor)
            {
                read = hit.Read;
            }
            else
            {
                // La lettura è condivisa: non dipende dal token di chi la fa partire.
                read = ReadAsync(key, asUser, requestedBy);
                _cache[key] = (read, time.GetUtcNow());
            }
        }

        return read.WaitAsync(ct);
    }

    /// <summary>Dimentica gli elenchi letti (dopo una modifica alle richieste).</summary>
    public void Clear()
    {
        lock (_lock)
        {
            _cache.Clear();
        }
    }

    private async Task<IReadOnlyList<SeerrRequest>> ReadAsync(int key, int asUser, int? requestedBy)
    {
        // Si cede subito il turno: se la lettura fallisse prima del primo await, la voce non sarebbe ancora in _cache.
        await Task.Yield();
        try
        {
            var all = new List<SeerrRequest>();
            var skip = 0;
            while (true)
            {
                var page = await seerr.GetRequestsAsync(asUser, "all", PageSize, skip, requestedBy, CancellationToken.None)
                    .ConfigureAwait(false);
                var results = page.Results ?? [];
                skip += results.Count;
                all.AddRange(results.OfType<SeerrRequest>());
                if (results.Count == 0 || skip >= (page.PageInfo?.Results ?? 0))
                {
                    return all;
                }
            }
        }
        catch
        {
            lock (_lock)
            {
                _cache.Remove(key);
            }

            throw;
        }
    }
}
