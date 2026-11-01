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

    // Un job: quando è partito e il lavoro. Result null nell'esito: titolo che Radarr/Sonarr non hanno.
    private sealed record SearchJob(DateTimeOffset StartedAt, Task<SearchOutcome> Work);

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
        job = new SearchJob(time.GetUtcNow(), Task.Run(() => RunSearchJobAsync(key)));
        _searchJobs[key.ToString()] = job;
        return job;
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
            { Work.IsCompleted: false } => new(key.ToString(), DownloadSearchStates.Running, job.StartedAt, service, null),
            { Work.Result: { Result: { } result } outcome } => new(key.ToString(), DownloadSearchStates.Done, outcome.At, service, result),
            _ => new(key.ToString(), DownloadSearchStates.Missing, job.StartedAt, service, null),
        };
    }

    // Lo stesso lavoro della vecchia ricerca: un errore di Radarr/Sonarr dà il DTO con Error e le liste vuote.
    private async Task<SearchOutcome> RunSearchJobAsync(DownloadKey key)
    {
        var (search, error) = await ReadAsync(ServiceOf(key.Kind), c => RunSearchAsync(key, c), _searchStop.Token).ConfigureAwait(false);
        if (error is null)
        {
            return new SearchOutcome(search?.At ?? time.GetUtcNow(), search?.Result);
        }

        string title;
        lock (_lock)
        {
            title = Book.Get(key.ToString())?.Title ?? "";
        }

        return new SearchOutcome(time.GetUtcNow(), new DownloadSearchDto(key.ToString(), key.Kind, title, 0, null, [], [], 0, 0, error, []));
    }

    // Solo sotto _lock. Un job dell'admin in corso sulla chiave, per la panoramica.
    private bool AdminSearching(string key) => _searchJobs.TryGetValue(key, out var job) && !job.Work.IsCompleted;
}
