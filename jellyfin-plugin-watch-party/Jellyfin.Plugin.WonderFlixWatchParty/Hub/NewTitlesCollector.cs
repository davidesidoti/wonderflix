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

    // 1 mentre una chiusura è in corso: il timer e "Send now" possono arrivare insieme.
    private int _closing;

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

    /// <summary>Chiude subito l'ondata ("Send now" nella Dashboard), anche durante una scansione.</summary>
    public Task<NewTitlesSendResponse> SendNowAsync() => CloseAsync(force: true);

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
            await CloseAsync(force: false).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Se l'ondata non è stata buttata (CloseFailed) si riprova al prossimo controllo.
            logger.LogWarning(ex, "Riepilogo dei nuovi titoli non riuscito");
        }
    }

    private async Task<NewTitlesSendResponse> CloseAsync(bool force)
    {
        if (Interlocked.Exchange(ref _closing, 1) == 1)
        {
            return Nothing;
        }

        try
        {
            if (!settings.NotifyNewTitles)
            {
                Discard();
                return Nothing;
            }

            NewTitlesWave? wave;
            List<Guid> ids;
            lock (_lock)
            {
                wave = _wave;
                ids = wave?.AddedIds.ToList() ?? [];
            }

            if (wave is null)
            {
                return Nothing;
            }

            var now = time.GetUtcNow();
            var due = force || wave.IsOverdue(now, MaxWait);
            if (!due && (!wave.IsQuiet(now, QuietTime) || library.IsScanRunning))
            {
                return Nothing;
            }

            var detached = false;
            List<LibraryTitle> kept;
            Dictionary<Guid, InboxEntry> entries;
            try
            {
                // Fuori dal lock: si legge dal database.
                var titles = new Dictionary<Guid, LibraryTitle>();
                Resolve(ids, titles);

                // Metadati non ancora arrivati (nome dal file, niente numeri): si
                // aspetta, entro MaxWait.
                if (!due && titles.Values.Any(t => !t.Refreshed))
                {
                    return Nothing;
                }

                lock (_lock)
                {
                    // L'ondata si stacca: quello che arriva da adesso apre la prossima.
                    _wave = null;
                    detached = true;
                    ids = wave.AddedIds.ToList();
                }

                Resolve(ids.Where(id => !titles.ContainsKey(id)), titles);
                kept = ids
                    .Where(titles.ContainsKey)
                    .Select(id => titles[id])
                    .Where(title => !wave.IsReplacement(title))
                    .ToList();
                entries = BuildEntries(kept, now);
            }
            catch (Exception)
            {
                CloseFailed(wave, detached);
                throw;
            }

            // Da qui non si lancia più: AddNewTitlesAsync tiene per sé i suoi errori.
            await inbox.AddNewTitlesAsync(entries).ConfigureAwait(false);
            logger.LogDebug("Nuovi titoli: ondata chiusa con {Titles} titoli per {Recipients} utenti", kept.Count, entries.Count);
            return new NewTitlesSendResponse(kept.Count, entries.Count);
        }
        finally
        {
            Volatile.Write(ref _closing, 0);
        }
    }

    /// <summary>
    /// Una chiusura non riuscita: niente è stato consegnato. L'ondata staccata
    /// torna in corso, con quello che è arrivato nel frattempo, e si riprova al
    /// prossimo controllo; dopo <see cref="MaxCloseAttempts"/> si butta.
    /// </summary>
    private void CloseFailed(NewTitlesWave wave, bool detached)
    {
        lock (_lock)
        {
            // Non staccata, ma buttata o sostituita mentre si leggeva: non c'è niente da contare.
            if (!detached && !ReferenceEquals(_wave, wave))
            {
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
        foreach (var user in users.GetUsers().Where(u => u.Enabled))
        {
            var userMovies = movies.Where(m => access.CanSee(user.Id, m.ItemId)).ToList();
            var userSeries = new List<NewTitleSeries>();
            foreach (var episodes in episodesBySeries)
            {
                var visible = episodes.Where(e => access.CanSee(user.Id, e.ItemId)).ToList();
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
