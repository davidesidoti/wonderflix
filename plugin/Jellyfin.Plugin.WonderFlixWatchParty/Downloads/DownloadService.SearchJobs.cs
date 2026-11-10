using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Le ricerche dell'admin in background (spec W §4.2-4.4): al più un job per chiave, con un token del servizio e mai quello
/// della richiesta, così una ricerca lunga finisce anche se l'admin chiude la pagina. Esito ed errore valgono
/// <see cref="SearchResultLifetime"/>.
/// </summary>
public sealed partial class DownloadService
{
    /// <summary>Quanto si mostra l'esito di una ricerca dell'admin, circa quanto Radarr/Sonarr ricordano le release (spec W §4.3).</summary>
    public static readonly TimeSpan SearchResultLifetime = TimeSpan.FromMinutes(30);

    // Si annulla allo spegnimento del plugin (StopSearches).
    private readonly CancellationTokenSource _searchStop = new();

    // Solo sotto _lock. Il job dell'admin per chiave: in corso finché Work non finisce. A parte da _searching, così la
    // fine di una ricerca del giro non toglie "Searching" a un job dell'admin.
    private readonly Dictionary<string, SearchJob> _searchJobs = [];

    // Solo sotto _lock. Le ricerche dell'admin (job, "scarica il migliore", una nuova ricerca per un grab) che aspettano o sono in corso.
    private int _manualSearches;

    // Solo sotto _lock. Si completa quando il giro non cerca più niente: lo aspettano le ricerche dell'admin.
    private TaskCompletionSource? _autoIdle;

    // Un job: quando è partito (prima la creazione, poi l'inizio vero della ricerca) e il lavoro. Started e StartedAt solo sotto _lock.
    // Result null nell'esito: titolo che Radarr/Sonarr non hanno.
    private sealed class SearchJob(DateTimeOffset createdAt)
    {
        public DateTimeOffset StartedAt { get; set; } = createdAt;

        public bool Started { get; set; }

        public Task<SearchOutcome> Work { get; set; } = null!;
    }

    // At: l'ora della ricerca (o dell'errore), da cui contano i 30 minuti.
    private sealed record SearchOutcome(DateTimeOffset At, DownloadSearchDto? Result);

    /// <summary>
    /// Avvia la ricerca dell'admin, o restituisce quella in corso o un esito con meno di 30 minuti; con <paramref name="again"/>
    /// ne avvia una nuova se non ce n'è una in corso (spec W §4.4). Null per una chiave non valida.
    /// </summary>
    public DownloadSearchStatusDto? StartSearch(string key, bool again)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return null;
        }

        lock (_lock)
        {
            return StatusOf(parsed, JobFor(parsed, again));
        }
    }

    /// <summary>Lo stato della ricerca dell'admin senza avviarne una (spec W §4.4). Null per una chiave non valida.</summary>
    public DownloadSearchStatusDto? SearchStatus(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return null;
        }

        lock (_lock)
        {
            return StatusOf(parsed, CurrentJob(parsed.ToString()));
        }
    }

    /// <summary>Annulla le ricerche dell'admin in corso, allo spegnimento del plugin.</summary>
    public void StopSearches() => _searchStop.Cancel();

    // Solo sotto _lock. Il job in corso o con un esito valido, altrimenti (o con again, se è finito) uno nuovo.
    private SearchJob JobFor(DownloadKey key, bool again)
    {
        // CurrentJob toglie gli esiti scaduti: i job non restano in memoria per sempre.
        foreach (var k in _searchJobs.Keys.ToList())
        {
            CurrentJob(k);
        }

        if (CurrentJob(key.ToString()) is { } job && !(again && job.Work.IsCompleted))
        {
            return job;
        }

        // In un altro thread: il job prende _lock per conto suo e non gira dentro questo.
        var created = new SearchJob(time.GetUtcNow());
        created.Work = Task.Run(() => RunSearchJobAsync(key, created));
        _searchJobs[key.ToString()] = created;
        return created;
    }

    // Solo sotto _lock. Il job della chiave, se è in corso o finito da meno di 30 minuti; uno annullato non conta.
    private SearchJob? CurrentJob(string key)
    {
        if (!_searchJobs.TryGetValue(key, out var job) || !job.Work.IsCompleted)
        {
            return job;
        }

        if (job.Work.IsCompletedSuccessfully && time.GetUtcNow() - job.Work.Result.At < SearchResultLifetime)
        {
            return job;
        }

        _searchJobs.Remove(key);
        return null;
    }

    private DownloadSearchStatusDto StatusOf(DownloadKey key, SearchJob? job)
    {
        var service = ServiceOf(key.Kind).ToString();
        return job switch
        {
            null => new(key.ToString(), DownloadSearchStates.None, null, service, null),
            { Work.IsCompleted: false } => new(key.ToString(), DownloadSearchStates.Running, job.StartedAt, service, null, job.Started ? null : AutoSearchWait()),
            { Work.Result: { Result: { } result } outcome } => new(key.ToString(), DownloadSearchStates.Done, outcome.At, service, result),
            _ => new(key.ToString(), DownloadSearchStates.Missing, job.StartedAt, service, null),
        };
    }

    // Lo stesso lavoro della vecchia ricerca: un errore di Radarr/Sonarr dà il DTO con Error e le liste vuote.
    private async Task<SearchOutcome> RunSearchJobAsync(DownloadKey key, SearchJob job)
    {
        var (search, error) = await ReadAsync(ServiceOf(key.Kind), c => RunSearchAsync(key, c, job), _searchStop.Token).ConfigureAwait(false);
        if (error is null)
        {
            return new SearchOutcome(search?.At ?? time.GetUtcNow(), search?.Result);
        }

        string title;
        lock (_lock)
        {
            title = Book.Get(key.ToString())?.Title ?? "";
        }

        return new SearchOutcome(time.GetUtcNow(), new DownloadSearchDto(key.ToString(), key.Kind, title, 0, null, [], [], 0, 0, error, [], null));
    }

    // Solo sotto _lock. Un job dell'admin in corso sulla chiave, per la panoramica.
    private bool AdminSearching(string key) => _searchJobs.TryGetValue(key, out var job) && !job.Work.IsCompleted;

    // Solo sotto _lock. Una ricerca dell'admin aspetta o è in corso (anche un job appena creato che non è ancora partito).
    private bool ManualSearching() => _manualSearches > 0 || _searchJobs.Values.Any(j => !j.Work.IsCompleted);

    // Solo sotto _lock. La ricerca automatica in corso (la più vecchia), null se il giro non cerca niente.
    private SearchWaitDto? AutoSearchWait()
    {
        if (_searching.Count == 0)
        {
            return null;
        }

        var (key, since) = _searching.MinBy(s => s.Value);
        int? typical = _autoDurations.Count < TypicalMinimum ? null : (int)Math.Round(_autoDurations.Average());
        return new SearchWaitDto(Book.Get(key)?.Title ?? key, since, typical);
    }

    // Ogni ricerca dell'admin passa da qui: aspetta che finisca la ricerca automatica in corso (il giro intanto non ne avvia
    // altre), poi cerca; più ricerche dell'admin vanno insieme. L'attesa non conta nel timeout della ricerca, che vale solo
    // per la richiesta a Radarr/Sonarr. Alla fine dell'ultima, se il giro si era fermato, se ne chiede uno (Nudge).
    private async Task<AdminSearch?> RunSearchAsync(DownloadKey key, CancellationToken cancellationToken, SearchJob? job = null)
    {
        lock (_lock)
        {
            _manualSearches++;
        }

        var resume = false;
        try
        {
            while (true)
            {
                Task idle;
                lock (_lock)
                {
                    if (_searching.Count == 0)
                    {
                        if (job is not null)
                        {
                            job.Started = true;
                            job.StartedAt = time.GetUtcNow();
                        }

                        break;
                    }

                    idle = (_autoIdle ??= new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)).Task;
                }

                await idle.WaitAsync(cancellationToken).ConfigureAwait(false);
            }

            return await SearchForAdminAsync(key, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            lock (_lock)
            {
                _manualSearches--;
                if (_manualSearches == 0 && _heldForManual)
                {
                    (_heldForManual, resume) = (false, true);
                }
            }

            if (resume)
            {
                Nudge();
            }
        }
    }
}
