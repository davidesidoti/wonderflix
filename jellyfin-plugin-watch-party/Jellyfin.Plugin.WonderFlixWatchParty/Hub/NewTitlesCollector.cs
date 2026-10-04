using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Il riepilogo dei nuovi titoli (spec G §6.6). Raccoglie in un'ondata i
/// film e gli episodi aggiunti alla libreria; ogni <see cref="CheckInterval"/>
/// guarda se chiuderla: dopo <see cref="QuietTime"/> senza novità, se la
/// scansione è finita e i metadati ci sono, e comunque dopo
/// <see cref="MaxWait"/>. Alla chiusura ogni utente attivo riceve una voce
/// con i film che può vedere e gli episodi (che può vedere) delle serie che
/// segue. Added e Removed arrivano dai thread della scansione: sono O(1)
/// sotto lock; il lavoro sul database si fa alla chiusura. Con la casella
/// spenta non si raccoglie e l'ondata in corso si butta.
/// </summary>
public sealed class NewTitlesCollector(
    ILibraryTitles library,
    ILibraryAccess access,
    IUserDirectory users,
    InboxService inbox,
    INewTitlesSettings settings,
    TimeProvider time,
    ILogger<NewTitlesCollector> logger) : IDisposable
{
    /// <summary>Senza novità per questo tempo l'ondata si chiude (spec G §6.6).</summary>
    public static readonly TimeSpan QuietTime = TimeSpan.FromMinutes(15);

    /// <summary>Dopo questo tempo dal primo titolo l'ondata si chiude comunque.</summary>
    public static readonly TimeSpan MaxWait = TimeSpan.FromHours(2);

    /// <summary>Ogni quanto si guarda se l'ondata si può chiudere.</summary>
    public static readonly TimeSpan CheckInterval = TimeSpan.FromMinutes(1);

    /// <summary>Righe al massimo per voce (un film o una serie = una riga); le altre si contano in More.</summary>
    public const int MaxLines = 500;

    /// <summary>Chiusure non riuscite di fila dopo cui l'ondata si butta.</summary>
    public const int MaxCloseAttempts = 5;

    private static readonly NewTitlesSendResponse Nothing = new(0, 0);

    private readonly Lock _lock = new();
    private NewTitlesWave? _wave;
    private ITimer? _timer;

    // Quante volte l'ondata è stata buttata (casella spenta), sotto _lock: una
    // chiusura non riuscita rimette la sua ondata staccata solo se non è cambiato.
    private long _discards;

    // Una chiusura alla volta: il timer e "Send now" possono arrivare insieme.
    // Il controllo del timer salta se è occupato, "Send now" aspetta il suo turno.
    private readonly SemaphoreSlim _closing = new(1, 1);

    /// <summary>Titoli in attesa nell'ondata in corso; 0 con la casella spenta (e l'ondata si butta).</summary>
    public int Pending
    {
        get
        {
            if (!settings.NotifyNewTitles)
            {
                Discard();
                return 0;
            }

            lock (_lock)
            {
                return _wave?.Count ?? 0;
            }
        }
    }

    /// <summary>Fa partire il controllo periodico (all'avvio del plugin).</summary>
    public void Start()
    {
        lock (_lock)
        {
            _timer ??= time.CreateTimer(_ => _ = CheckSafelyAsync(), null, CheckInterval, CheckInterval);
        }
    }

    /// <summary>Un film o un episodio vero aggiunto alla libreria.</summary>
    public void Added(Guid itemId)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return;
        }

        lock (_lock)
        {
            Current().Add(itemId, time.GetUtcNow());
        }
    }

    /// <summary>Un film o un episodio vero tolto dalla libreria, con i suoi id esterni.</summary>
    public void Removed(Guid itemId, bool isMovie, IReadOnlyCollection<string> externalKeys)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return;
        }

        lock (_lock)
        {
            Current().Remove(itemId, isMovie, externalKeys, time.GetUtcNow());
        }
    }

    /// <summary>
    /// La cartella vera di una serie (season null, con i suoi id esterni) o
    /// di una stagione tolta, con la chiave della serie: i suoi episodi che
    /// tornano in questa ondata (cartella rinominata) non si annunciano.
    /// </summary>
    public void RemovedSeries(string seriesKey, int? season, IReadOnlyCollection<string> seriesExternalKeys)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return;
        }

        lock (_lock)
        {
            Current().RemoveSeries(seriesKey, season, seriesExternalKeys, time.GetUtcNow());
        }
    }

    /// <summary>
    /// Chiude subito l'ondata ("Send now" nella Dashboard), anche durante una
    /// scansione; se un controllo la sta già chiudendo, aspetta che finisca.
    /// </summary>
    public async Task<NewTitlesSendResponse> SendNowAsync()
    {
        await _closing.WaitAsync().ConfigureAwait(false);
        try
        {
            return await CloseAsync(force: true).ConfigureAwait(false);
        }
        finally
        {
            _closing.Release();
        }
    }

    // _closing non si chiude: un controllo ancora in corso lo rilascia alla
    // fine, e con il semaforo chiuso Release lancerebbe (un riepilogo già
    // consegnato finirebbe nel log come non riuscito). AvailableWaitHandle non
    // si usa, quindi non c'è niente da liberare.
    public void Dispose()
    {
        lock (_lock)
        {
            _timer?.Dispose();
            _timer = null;
        }
    }

    private async Task CheckSafelyAsync()
    {
        try
        {
            // Una chiusura già in corso (un altro controllo o "Send now"): si salta.
            if (!_closing.Wait(0))
            {
                return;
            }

            try
            {
                await CloseAsync(force: false).ConfigureAwait(false);
            }
            finally
            {
                _closing.Release();
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Se l'ondata non è stata buttata (CloseFailed) si riprova al prossimo controllo.
            logger.LogWarning(ex, "Riepilogo dei nuovi titoli non riuscito");
        }
    }

    // Solo con _closing preso: una chiusura alla volta.
    private async Task<NewTitlesSendResponse> CloseAsync(bool force)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return Nothing;
        }

        NewTitlesWave? wave;
        List<Guid> ids;
        DateTimeOffset now;
        DateTimeOffset lastChangeAt;
        bool due;
        long discards;
        lock (_lock)
        {
            wave = _wave;
            if (wave is null)
            {
                return Nothing;
            }

            now = time.GetUtcNow();
            due = force || wave.IsOverdue(now, MaxWait);
            if (!due && !wave.IsQuiet(now, QuietTime))
            {
                // Un controllo senza errori: le chiusure non riuscite di fila ripartono da zero.
                wave.ResetFailedCloses();
                return Nothing;
            }

            lastChangeAt = wave.LastChangeAt;
            ids = wave.AddedIds.ToList();
            discards = _discards;
        }

        var detached = false;
        var failed = false;
        List<LibraryTitle> kept;
        Dictionary<Guid, InboxEntry> entries;
        try
        {
            // Durante una scansione arrivano altri titoli: si aspetta, entro MaxWait.
            if (!due && library.IsScanRunning)
            {
                return Nothing;
            }

            // Fuori dal lock: si legge dal database. Metadati non ancora
            // arrivati (nome dal file, niente numeri): si aspetta, entro
            // MaxWait, e basta il primo titolo senza per non leggere gli altri.
            var titles = new Dictionary<Guid, LibraryTitle>();
            foreach (var id in ids)
            {
                if (library.Get(id) is not { } title)
                {
                    continue;
                }

                if (!due && !title.Refreshed)
                {
                    return Nothing;
                }

                titles[id] = title;
            }

            lock (_lock)
            {
                // Buttata (casella spenta) o sostituita mentre si leggeva: non si
                // manda. Arrivato un titolo: niente più quiete, si chiuderà a un
                // prossimo controllo (se è scaduta si chiude adesso, con lui).
                if (!ReferenceEquals(_wave, wave) || (!due && wave.LastChangeAt != lastChangeAt))
                {
                    return Nothing;
                }

                // L'ondata si stacca: quello che arriva da adesso apre la prossima.
                _wave = null;
                detached = true;
                ids = wave.AddedIds.ToList();
            }

            // I titoli già letti si tengono: si leggono solo quelli arrivati nel frattempo.
            Resolve(ids.Where(id => !titles.ContainsKey(id)), titles);
            kept = ids
                .Where(titles.ContainsKey)
                .Select(id => titles[id])
                .Where(title => !wave.IsReplacement(title))
                .ToList();
            entries = BuildEntries(kept, now);

            // Casella spenta mentre si leggeva, dopo il distacco: l'ondata non si
            // manda (e se è spenta adesso si butta anche quella più nuova).
            var enabled = settings.NotifyNewTitles;
            bool dropped;
            lock (_lock)
            {
                dropped = !enabled || _discards != discards;
            }

            if (dropped)
            {
                if (!enabled)
                {
                    Discard();
                }

                logger.LogDebug("Nuovi titoli: ondata scartata con {Titles} titoli, casella spenta durante la chiusura", kept.Count);
                return Nothing;
            }
        }
        catch (Exception)
        {
            failed = true;
            CloseFailed(wave, detached, discards);
            throw;
        }
        finally
        {
            // Letto senza errori, ma non è il momento (o l'ondata è cambiata):
            // le chiusure non riuscite di fila ripartono da zero.
            if (!failed && !detached)
            {
                lock (_lock)
                {
                    wave.ResetFailedCloses();
                }
            }
        }

        // Da qui non si lancia più: AddNewTitlesAsync tiene per sé i suoi errori.
        await inbox.AddNewTitlesAsync(entries).ConfigureAwait(false);
        logger.LogDebug("Nuovi titoli: ondata chiusa con {Titles} titoli per {Recipients} utenti", kept.Count, entries.Count);
        return new NewTitlesSendResponse(kept.Count, entries.Count);
    }

    /// <summary>
    /// Una chiusura non riuscita: niente è stato consegnato. L'ondata staccata
    /// torna in corso, con quello che è arrivato nel frattempo, e si riprova al
    /// prossimo controllo; dopo <see cref="MaxCloseAttempts"/> di fila si
    /// butta. Se nel frattempo la casella è stata spenta (discards cambiato)
    /// non torna.
    /// </summary>
    private void CloseFailed(NewTitlesWave wave, bool detached, long discards)
    {
        lock (_lock)
        {
            // Non staccata, ma buttata o sostituita mentre si leggeva: non c'è niente da contare.
            if (!detached && !ReferenceEquals(_wave, wave))
            {
                return;
            }

            // Staccata e buttata nel frattempo: l'ondata più nuova, se c'è, resta com'è.
            if (detached && _discards != discards)
            {
                logger.LogDebug("Nuovi titoli: ondata scartata con {Count} titoli, casella spenta durante la chiusura", wave.Count);
                return;
            }

            var attempts = wave.RecordFailedClose();
            if (attempts >= MaxCloseAttempts)
            {
                // Staccata: l'ondata più nuova, se c'è, resta com'è.
                if (!detached)
                {
                    _wave = null;
                }

                logger.LogWarning(
                    "Nuovi titoli: ondata scartata con {Count} titoli dopo {Attempts} chiusure non riuscite",
                    wave.Count,
                    attempts);
                return;
            }

            if (detached)
            {
                if (_wave is { } newer)
                {
                    wave.Absorb(newer);
                }

                _wave = wave;
            }
        }
    }

    private void Resolve(IEnumerable<Guid> ids, Dictionary<Guid, LibraryTitle> titles)
    {
        foreach (var id in ids)
        {
            if (library.Get(id) is { } title)
            {
                titles[id] = title;
            }
        }
    }

    private Dictionary<Guid, InboxEntry> BuildEntries(List<LibraryTitle> titles, DateTimeOffset now)
    {
        var entries = new Dictionary<Guid, InboxEntry>();
        if (titles.Count == 0)
        {
            return entries;
        }

        var movies = titles.Where(t => t.IsMovie).OrderBy(t => t.Name, StringComparer.OrdinalIgnoreCase).ToList();
        var episodesBySeries = titles.Where(t => !t.IsMovie && t.SeriesId != Guid.Empty).GroupBy(t => t.SeriesId).ToList();
        var anyWithoutMetadata = titles.Any(t => !t.Refreshed);
        foreach (var user in users.GetUsers().Where(u => u.Enabled))
        {
            // Titoli senza metadati (chiusura forzata o dopo MaxWait): niente
            // classificazione né tag, i limiti del profilo non li fermerebbero.
            // Vanno solo a chi non ha limiti sui contenuti.
            var limited = anyWithoutMetadata && access.HasContentLimits(user.Id);
            bool Allowed(LibraryTitle title) => title.Refreshed || !limited;

            var userMovies = movies.Where(m => Allowed(m) && access.CanSee(user.Id, m.ItemId)).ToList();
            var userSeries = new List<NewTitleSeries>();
            foreach (var episodes in episodesBySeries)
            {
                var visible = episodes.Where(e => Allowed(e) && access.CanSee(user.Id, e.ItemId)).ToList();
                if (visible.Count == 0)
                {
                    continue;
                }

                var first = visible[0];
                var newEpisodes = episodes.Select(e => e.ItemId).ToList();
                if (!library.FollowsSeries(user.Id, episodes.Key, first.SeriesKey, newEpisodes))
                {
                    continue;
                }

                userSeries.Add(new NewTitleSeries
                {
                    SeriesId = episodes.Key.ToString("N"),
                    Name = first.SeriesName,
                    Episodes = visible
                        .OrderBy(e => e.Season ?? int.MaxValue)
                        .ThenBy(e => e.Episode ?? int.MaxValue)
                        .Select(e => new NewTitleEpisode { Season = e.Season, Episode = e.Episode })
                        .ToList(),
                });
            }

            if (userMovies.Count + userSeries.Count == 0)
            {
                continue;
            }

            entries[user.Id] = Entry(
                userMovies, userSeries.OrderBy(s => s.Name, StringComparer.OrdinalIgnoreCase).ToList(), now);
        }

        return entries;
    }

    private static InboxEntry Entry(List<LibraryTitle> movies, List<NewTitleSeries> series, DateTimeOffset now)
    {
        var lines = movies.Count + series.Count;
        var movieLines = movies
            .Take(MaxLines)
            .Select(m => new NewTitleMovie { ItemId = m.ItemId.ToString("N"), Name = m.Name, Year = m.Year })
            .ToList();
        return new InboxEntry
        {
            Type = InboxEntryTypes.NewTitles,
            CreatedAt = now,
            Movies = movieLines,
            Series = series.Take(MaxLines - movieLines.Count).ToList(),
            More = lines > MaxLines ? lines - MaxLines : null,
        };
    }

    private void Discard()
    {
        lock (_lock)
        {
            // Anche senza ondata in corso: quella staccata da una chiusura non deve tornare.
            _discards++;
            if (_wave is { Count: > 0 })
            {
                logger.LogDebug("Nuovi titoli: ondata scartata con {Count} titoli, casella spenta", _wave.Count);
            }

            _wave = null;
        }
    }

    // Solo sotto _lock.
    private NewTitlesWave Current() => _wave ??= new NewTitlesWave(time.GetUtcNow());
}
