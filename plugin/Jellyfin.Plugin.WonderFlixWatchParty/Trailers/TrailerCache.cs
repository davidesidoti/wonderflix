namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>
/// I trailer scaricati, <c>&lt;id&gt;.mp4</c> in una cartella. Un file sparisce un'ora dopo l'ultima visione
/// (<see cref="KeepFor"/>), mai finché qualcuno lo sta leggendo (<see cref="OpenLease"/>), e la cartella
/// non supera <see cref="MaxBytes"/>. L'ultima visione sta in memoria: dopo un riavvio i file trovati
/// ripartono da adesso. Sicura tra thread.
/// </summary>
public sealed class TrailerCache
{
    public static readonly TimeSpan KeepFor = TimeSpan.FromMinutes(60);

    public const long MaxBytes = 1L << 30;

    /// <summary>Un file <c>.part</c> più vecchio di così non lo scrive più nessuno.</summary>
    private static readonly TimeSpan PartLife = TimeSpan.FromMinutes(10);

    private readonly string _folder;
    private readonly TimeProvider _time;
    private readonly object _gate = new();
    private readonly Dictionary<string, DateTimeOffset> _seen = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, int> _leases = new(StringComparer.OrdinalIgnoreCase);

    public TrailerCache(string folder, TimeProvider time)
    {
        _folder = folder;
        _time = time;
        Directory.CreateDirectory(folder);
    }

    /// <summary>Svuota la cartella: all'avvio i file di un'altra vita non servono.</summary>
    public void Clear()
    {
        lock (_gate)
        {
            Directory.CreateDirectory(_folder);
            foreach (var file in Directory.EnumerateFiles(_folder))
            {
                TryDelete(file);
            }

            _seen.Clear();
        }
    }

    public string PathFor(string videoId) => Path.Combine(_folder, videoId + ".mp4");

    /// <summary>Il file c'è; se sì conta come visto adesso.</summary>
    public bool Has(string videoId)
    {
        if (!File.Exists(PathFor(videoId)))
        {
            return false;
        }

        Touch(videoId);
        return true;
    }

    public void Touch(string videoId)
    {
        lock (_gate)
        {
            _seen[videoId] = _time.GetUtcNow();
        }
    }

    /// <summary>Finché la lease è aperta il file non si cancella; chiuderla vale una visione.</summary>
    public IDisposable OpenLease(string videoId)
    {
        lock (_gate)
        {
            _leases[videoId] = _leases.GetValueOrDefault(videoId) + 1;
        }

        return new Lease(this, videoId);
    }

    /// <summary>Toglie i file non visti da <see cref="KeepFor"/> e gli avanzi di download interrotti.</summary>
    public void Sweep()
    {
        lock (_gate)
        {
            var now = _time.GetUtcNow();
            foreach (var file in Directory.EnumerateFiles(_folder))
            {
                if (IsPart(file))
                {
                    if (now - File.GetLastWriteTimeUtc(file) > PartLife)
                    {
                        TryDelete(file);
                    }

                    continue;
                }

                var id = Path.GetFileNameWithoutExtension(file);
                if (_leases.ContainsKey(id))
                {
                    continue;
                }

                if (!_seen.TryGetValue(id, out var seen))
                {
                    _seen[id] = now; // arrivato senza passare di qui
                }
                else if (now - seen > KeepFor && TryDelete(file))
                {
                    _seen.Remove(id);
                }
            }
        }
    }

    /// <summary>Fa posto a <paramref name="incomingBytes"/> togliendo i file visti meno di recente, mai quelli in lettura.</summary>
    public void MakeRoom(long incomingBytes = 200L << 20)
    {
        lock (_gate)
        {
            var files = Directory.EnumerateFiles(_folder).Select(f => new FileInfo(f)).ToList();
            var total = files.Sum(f => f.Length);
            var now = _time.GetUtcNow();
            var oldestFirst = files
                .Where(f => !IsPart(f.Name) && !_leases.ContainsKey(Path.GetFileNameWithoutExtension(f.Name)))
                .OrderBy(f => _seen.GetValueOrDefault(Path.GetFileNameWithoutExtension(f.Name), now));
            foreach (var file in oldestFirst)
            {
                if (total + incomingBytes <= MaxBytes)
                {
                    return;
                }

                var length = file.Length;
                if (TryDelete(file.FullName))
                {
                    total -= length;
                    _seen.Remove(Path.GetFileNameWithoutExtension(file.Name));
                }
            }
        }
    }

    private static bool IsPart(string path) => Path.GetFileName(path).Contains(".part", StringComparison.OrdinalIgnoreCase);

    private static bool TryDelete(string path)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private sealed class Lease(TrailerCache cache, string videoId) : IDisposable
    {
        private int _disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 1)
            {
                return;
            }

            lock (cache._gate)
            {
                if (cache._leases[videoId] <= 1)
                {
                    cache._leases.Remove(videoId);
                }
                else
                {
                    cache._leases[videoId]--;
                }

                cache._seen[videoId] = cache._time.GetUtcNow();
            }
        }
    }
}
