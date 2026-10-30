using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Esito di un giro (spec T §5): ricerche fatte, release scaricate e l'errore di ciascun servizio.</summary>
public sealed record CycleReport(int Searched, int Grabbed, string? SonarrError, string? RadarrError);

/// <summary>
/// I download automatici (spec T §5): il giro che sceglie i titoli da seguire,
/// segue la coda di Radarr e Sonarr e cerca quelli che mancano (DownloadService.Search.cs).
/// Stato in <see cref="DownloadBook"/>, su disco con <see cref="DownloadStore"/>. Sicuro tra
/// thread: il libro sta sotto un lock che non resta mai preso durante una chiamata a Radarr o Sonarr.
/// </summary>
public sealed partial class DownloadService(
    IArrClient arr,
    IArrSettings arrSettings,
    IDownloadSettings settings,
    DownloadStore store,
    TimeProvider time,
    ILogger<DownloadService> logger)
{
    /// <summary>Un giro ogni tanto (decisione 7).</summary>
    public static readonly TimeSpan CycleInterval = TimeSpan.FromMinutes(15);

    /// <summary>Ricerche al massimo in un giro (decisione 7).</summary>
    public const int MaxSearchesPerCycle = 10;

    /// <summary>Pausa tra una ricerca e l'altra, per non martellare gli indexer (decisione 7).</summary>
    public static readonly TimeSpan PauseBetweenSearches = TimeSpan.FromSeconds(10);

    /// <summary>Ogni quanto si rifà l'elenco da ripassare (decisione 7).</summary>
    public static readonly TimeSpan ReviewInterval = TimeSpan.FromHours(24);

    /// <summary>Dopo un'approvazione: il tempo che Seerr aggiunga il titolo a Radarr/Sonarr (decisione 7).</summary>
    public static readonly TimeSpan NudgeDelay = TimeSpan.FromMinutes(1);

    // Lo stato di un elemento della coda che aspetta l'admin (spec T §2).
    private const string ImportBlockedState = "importBlocked";

    // Status e trackedDownloadState di un elemento che sta scaricando: solo lui può essere fermo.
    private const string DownloadingState = "downloading";

    // Status di un torrent senza connessioni (stalledDL di qBittorrent, visto su Sonarr): scarica, ma niente (ruling 11).
    private const string WarningStatus = "warning";

    private readonly Lock _lock = new();
    private DownloadBook? _book;
    private (string? Sonarr, string? Radarr) _lastErrors;

    /// <summary>Pausa tra le ricerche; i test la mettono a zero.</summary>
    internal TimeSpan Pause { get; init; } = PauseBetweenSearches;

    /// <summary>Qualcuno chiede un giro presto (SearchNow, un'approvazione); lo ascolta il servizio in background.</summary>
    public event Action? Nudged;

    /// <summary>Gli errori dell'ultimo giro, per la panoramica.</summary>
    internal (string? Sonarr, string? Radarr) LastErrors
    {
        get
        {
            lock (_lock)
            {
                return _lastErrors;
            }
        }
    }

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private DownloadBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Download automatici in {Path}", store.FilePath);
            }

            return _book;
        }
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Book;
        }
    }

    /// <summary>Chiede un giro presto.</summary>
    public void Nudge() => Nudged?.Invoke();

    /// <summary>
    /// Un giro (spec T §5): legge Radarr e Sonarr, poi aggiorna le voci sotto il lock e
    /// salva. Un servizio non configurato o che non risponde lascia le sue voci come sono.
    /// Spento (ruling 12): segue solo le voci che ci sono già, senza crearne, cercare o togliere download fermi.
    /// </summary>
    public async Task<CycleReport> RunCycleAsync(CancellationToken cancellationToken)
    {
        var enabled = settings.Enabled;
        var radarr = await ReadAsync(ArrKind.Radarr, ReadRadarrAsync, cancellationToken).ConfigureAwait(false);
        var sonarr = await ReadAsync(ArrKind.Sonarr, ReadSonarrAsync, cancellationToken).ConfigureAwait(false);

        var now = time.GetUtcNow();
        var stalled = new List<(ArrKind Kind, int QueueId, string Key)>();
        var checks = new List<UpgradeCheck>();
        var imports = new List<ManualImport>();
        var views = new Dictionary<ArrKind, ArrView>();
        lock (_lock)
        {
            if (radarr.Value is { } movies)
            {
                Apply(ArrKind.Radarr, movies, now, enabled, stalled, checks, imports);
                views[ArrKind.Radarr] = movies;
            }

            if (sonarr.Value is { } episodes)
            {
                var view = GroupSeasons(episodes, now, enabled);
                Apply(ArrKind.Sonarr, view, now, enabled, stalled, checks, imports);
                views[ArrKind.Sonarr] = view;
            }
        }

        var errors = new Dictionary<ArrKind, string?> { [ArrKind.Radarr] = radarr.Error, [ArrKind.Sonarr] = sonarr.Error };
        var (searched, grabbed) = (0, 0);
        try
        {
            foreach (var (kind, queueId, key) in stalled)
            {
                await RemoveStalledAsync(kind, queueId, key, cancellationToken).ConfigureAwait(false);
            }

            foreach (var import in imports)
            {
                await ImportByHandAsync(import, cancellationToken).ConfigureAwait(false);
            }

            foreach (var check in checks)
            {
                await ConfirmUpgradeAsync(check, cancellationToken).ConfigureAwait(false);
            }

            if (enabled)
            {
                (searched, grabbed) = await SearchDueAsync(views, errors, cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            // Anche se il giro si interrompe a metà: i download già partiti non vanno persi.
            lock (_lock)
            {
                _lastErrors = (errors[ArrKind.Sonarr], errors[ArrKind.Radarr]);
                Book.Prune(now);

                // Sotto il lock come gli altri store: il libro non è sicuro tra thread e la scrittura è breve.
                store.Save(Book);
            }
        }

        return new CycleReport(searched, grabbed, errors[ArrKind.Sonarr], errors[ArrKind.Radarr]);
    }

    // Quello che un servizio dice di un titolo, già nella forma di una voce.
    private sealed record ArrTitle(
        string Key,
        string Kind,
        string Title,
        string? PosterUrl,
        int ProfileId,
        int RuntimeMinutes,
        DateTimeOffset? AvailableSince,
        bool Monitored,
        bool Followed,
        bool Wanted,
        bool HasFile,
        int FileId = 0,
        int SeriesId = 0,
        int EpisodeNumber = 0);

    // La lettura di un servizio: i suoi titoli per chiave e la coda per chiave.
    // AbsentHasFile: Sonarr toglie dai mancanti un episodio appena ha il file.
    // Solo Sonarr: le stagioni con episodi mancanti e la coda di ogni stagione (DownloadService.Seasons.cs).
    private sealed record ArrView(
        IReadOnlyDictionary<string, ArrTitle> Titles,
        IReadOnlyDictionary<string, ArrQueueItem> Queue,
        bool AbsentHasFile,
        IReadOnlyDictionary<string, ArrSeason>? Seasons = null,
        IReadOnlyDictionary<string, IReadOnlyList<ArrQueueItem>>? SeasonQueue = null);

    private async Task<(T? Value, string? Error)> ReadAsync<T>(
        ArrKind kind, Func<CancellationToken, Task<T>> read, CancellationToken cancellationToken)
        where T : class?
    {
        if (!arrSettings.Endpoint(kind).IsConfigured)
        {
            return (null, UpcomingErrors.NotConfigured);
        }

        try
        {
            return (await read(cancellationToken).ConfigureAwait(false), null);
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Download automatici: {Kind} non ha risposto ({Error})", kind, ex.Error);
            return (null, UpcomingErrors.Code(ex.Error));
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(ex, "Download automatici: errore leggendo {Kind}", kind);
            return (null, UpcomingErrors.Unreachable);
        }
    }

    private async Task<ArrView> ReadRadarrAsync(CancellationToken cancellationToken)
    {
        // Prima la coda: un import che finisce tra le due letture sembra così ancora in coda, mai fallito.
        var queue = await arr.GetQueueAsync(ArrKind.Radarr, cancellationToken).ConfigureAwait(false);
        var movies = await arr.GetLibraryMoviesAsync(cancellationToken).ConfigureAwait(false);
        var titles = movies.OfType<RadarrMovie>().Select(MovieTitleOf);
        return new ArrView(
            ByKey(titles, t => t.Key),
            ByKey(queue.OfType<ArrQueueItem>().Where(q => q.MovieId > 0), q => Key(DownloadKinds.Movie, q.MovieId!.Value)),
            AbsentHasFile: false);
    }

    private async Task<ArrView> ReadSonarrAsync(CancellationToken cancellationToken)
    {
        var queue = await arr.GetQueueAsync(ArrKind.Sonarr, cancellationToken).ConfigureAwait(false);
        var missing = await arr.GetMissingEpisodesAsync(cancellationToken).ConfigureAwait(false);
        var now = time.GetUtcNow();
        var episodes = missing.OfType<SonarrEpisode>().ToList();
        var titles = ByKey(episodes.Select(e => EpisodeTitleOf(e, now)), t => t.Key);
        var records = queue.OfType<ArrQueueItem>().ToList();
        return new ArrView(
            titles,
            ByKey(records.Where(q => q.EpisodeId > 0), q => Key(DownloadKinds.Episode, q.EpisodeId!.Value)),
            AbsentHasFile: true,
            await ReadSeasonsAsync(episodes, titles, now, cancellationToken).ConfigureAwait(false),
            SeasonQueueOf(records));
    }

    private static ArrTitle MovieTitleOf(RadarrMovie m) => new(
        Key(DownloadKinds.Movie, m.Id),
        DownloadKinds.Movie,
        string.Create(CultureInfo.InvariantCulture, $"{m.Title} ({m.Year})"),
        Poster(m.Images),
        m.QualityProfileId,
        m.Runtime,
        null,
        m.Monitored,
        Followed: m.Monitored && !m.HasFile,
        Wanted: m.Monitored && !m.HasFile && m.IsAvailable,
        m.HasFile,
        FileId: m.MovieFile?.Id ?? 0);

    // Un episodio mancante, con la sua serie in Series.
    private static ArrTitle EpisodeTitleOf(SonarrEpisode e, DateTimeOffset now) => new(
        Key(DownloadKinds.Episode, e.Id),
        DownloadKinds.Episode,
        string.Create(CultureInfo.InvariantCulture, $"{e.Series?.Title} · S{e.SeasonNumber:00}E{e.EpisodeNumber:00}"),
        Poster(e.Series?.Images),
        e.Series?.QualityProfileId ?? 0,
        e.Series?.Runtime ?? 0,
        e.AirDateUtc,
        e.Monitored,
        Followed: e.Monitored,
        Wanted: e.Monitored && e.AirDateUtc <= now,
        HasFile: false,
        SeriesId: e.SeriesId,
        EpisodeNumber: e.EpisodeNumber);

    internal static string SeasonTitleOf(string? series, int season) =>
        string.Create(CultureInfo.InvariantCulture, $"{series} · Stagione {season}");

    // Solo sotto _lock. Spento: niente voci nuove e niente download fermi da togliere (ruling 12).
    private void Apply(
        ArrKind kind,
        ArrView view,
        DateTimeOffset now,
        bool enabled,
        List<(ArrKind, int, string)> stalled,
        List<UpgradeCheck> checks,
        List<ManualImport> imports)
    {
        // 1-2. I titoli da seguire hanno una voce; quelle che ci sono si aggiornano.
        foreach (var title in view.Titles.Values.Where(t => t.Wanted))
        {
            if ((Book.Get(title.Key) ?? (enabled ? Create(title, now) : null)) is { } existing)
            {
                Describe(existing, title);
            }
        }

        // 3. La coda, anche quella che non ha avviato WonderFlix.
        foreach (var (key, item) in view.Queue)
        {
            var entry = Book.Get(key);
            if (entry is null)
            {
                // Un episodio che non manca non è da seguire (ha il file o non è monitorato).
                if (!enabled || !view.Titles.TryGetValue(key, out var title))
                {
                    continue;
                }

                entry = Create(title, now);
            }

            if (Track(entry, item, now, imports) && enabled)
            {
                // Un pack ha un elemento per episodio: si tolgono tutti, prima quello della voce.
                foreach (var queueId in view.SeasonQueue?.GetValueOrDefault(key)?.Select(q => q.Id) ?? [item.Id])
                {
                    stalled.Add((kind, queueId, key));
                }
            }
        }

        // 4-5. Download finiti e titoli da non seguire più.
        foreach (var entry in Book.Entries.Where(e => ServiceOf(e.Kind) == kind && !view.Queue.ContainsKey(e.Key)))
        {
            var title = view.Titles.GetValueOrDefault(entry.Key);

            // Scaricata da WonderFlix ma non ancora vista in coda.
            var grabbed = entry.QueueId is null && entry.State == DownloadStates.Downloading;
            if (entry.QueueId is not null || grabbed)
            {
                var hasFile = title is null ? view.AbsentHasFile : title.HasFile;
                var upgrade = entry.PreviousScore is not null;
                if (grabbed && entry.LastSearchAt is { } grabbedAt && now - grabbedAt < CycleInterval && (upgrade || !hasFile))
                {
                    // Radarr/Sonarr non l'hanno ancora messa in coda: riscaricarla farebbe due copie.
                    // Per un upgrade il file che c'è può essere ancora quello vecchio.
                }
                else if (hasFile && upgrade && UpgradeCheckOf(entry, title) is { } check)
                {
                    // Il file c'era già: se è cambiato lo dice solo il file (decisione 2 non basta).
                    checks.Add(check);
                }
                else if (hasFile)
                {
                    OnImported(entry, now);
                }
                else if (title?.Followed != true)
                {
                    // Fallito, ma il titolo non è più da seguire (tolto o non monitorato).
                    Book.Remove(entry.Key);
                }
                else
                {
                    // Radarr e Sonarr hanno già messo in blocklist la release fallita (decisione 2).
                    BackToWaiting(entry, now);
                }
            }
            else if (entry.State is DownloadStates.Waiting or DownloadStates.NeedsYou && title?.Followed != true)
            {
                Book.Remove(entry.Key);
            }
            else if (entry.State == DownloadStates.UpgradeWatch
                && (now >= entry.UpgradeUntil || (title is null ? !view.AbsentHasFile : !title.Monitored)))
            {
                // Finestra chiusa (lo riprende "Da ripassare"), o titolo tolto o non monitorato.
                // Un episodio col file non è tra i mancanti: si segue fino a UpgradeUntil.
                Book.Remove(entry.Key);
            }
        }
    }

    // Solo sotto _lock. True se il download è fermo da StalledAfter.
    private bool Track(DownloadEntry entry, ArrQueueItem item, DateTimeOffset now, List<ManualImport> imports)
    {
        // Fermo solo se scarica davvero: in coda, in pausa o col client giù l'orologio riparte (decisione 3).
        var active = IsActive(item);
        if (!active || entry.QueueId != item.Id || entry.LastSizeLeft != item.Sizeleft)
        {
            entry.QueueId = item.Id;
            entry.LastSizeLeft = item.Sizeleft;
            entry.LastProgressAt = now;
        }

        entry.State = DownloadStates.Downloading;
        entry.Reason = null;
        if (string.Equals(item.TrackedDownloadState, ImportBlockedState, StringComparison.OrdinalIgnoreCase))
        {
            OnImportBlocked(entry, item, imports);
            return false;
        }

        return active
            && entry.LastProgressAt is { } since
            && now - since >= DownloadSchedule.StalledAfter;
    }

    // Scarica (anche senza connessioni, "warning"): solo così può essere fermo (ruling 11).
    private static bool IsActive(ArrQueueItem item) =>
        string.Equals(item.TrackedDownloadState, DownloadingState, StringComparison.OrdinalIgnoreCase)
        && (string.Equals(item.Status, DownloadingState, StringComparison.OrdinalIgnoreCase)
            || string.Equals(item.Status, WarningStatus, StringComparison.OrdinalIgnoreCase));

    // Solo sotto _lock. Il file è arrivato: sotto l'obiettivo (o senza) si tengono d'occhio gli upgrade (spec T §5.3).
    private void OnImported(DownloadEntry entry, DateTimeOffset now)
    {
        logger.LogInformation("Download automatici: {Key} importato", entry.Key);
        var target = settings.For(ServiceOf(entry.Kind), entry.ProfileId, entry.ProfileName).TargetScore;

        // CurrentScore c'è solo per una scelta di WonderFlix: gli altri download non hanno upgrade (spec T §11).
        // Un titolo accettato ("va bene così" o "Alleggerisci") non ha upgrade.
        if (entry.CurrentScore is not { } score || score >= target || Book.IsAccepted(entry.Key))
        {
            Book.Remove(entry.Key);
            return;
        }

        var chosenAt = LatestChoice(entry.Key)?.At ?? now;
        entry.State = DownloadStates.UpgradeWatch;
        entry.Reason = null;
        entry.QueueId = null;
        entry.LastSizeLeft = null;
        entry.LastProgressAt = null;
        entry.PreviousScore = null;
        entry.PreviousQualityId = null;
        entry.PreviousSizeBytes = null;
        entry.UpgradeUntil = chosenAt + DownloadSchedule.UpgradeWindow;
        entry.NextSearchAt = DownloadSchedule.Next(chosenAt, now);
    }

    // Solo sotto _lock. Radarr/Sonarr non riescono a importare: serve l'admin. Una release scelta dall'admin che non
    // importerebbero si importa a mano, una volta sola: se al giro dopo è ancora bloccata, serve l'admin (decisione 9).
    private static void OnImportBlocked(DownloadEntry entry, ArrQueueItem item, List<ManualImport> imports)
    {
        var pending = entry.ManualImportPending && !string.IsNullOrEmpty(item.DownloadId);
        entry.ManualImportPending = false;
        if (pending)
        {
            imports.Add(new ManualImport(entry.Key, ServiceOf(entry.Kind), item.DownloadId!, item.Id));
            return;
        }

        entry.State = DownloadStates.NeedsYou;
        entry.Reason = DownloadReasons.ImportBlocked;
    }

    private async Task RemoveStalledAsync(ArrKind kind, int queueId, string key, CancellationToken cancellationToken)
    {
        try
        {
            await arr.RemoveFromQueueAsync(kind, queueId, blocklist: true, removeFromClient: true, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            // La voce resta com'è: il prossimo giro ci riprova.
            logger.LogWarning("Download automatici: {Key} fermo, {Kind} non l'ha tolto dalla coda ({Error})", key, kind, ErrorOf(ex));
            return;
        }

        logger.LogInformation("Download automatici: {Key} fermo da {Hours} ore, tolto dalla coda", key, DownloadSchedule.StalledAfter.TotalHours);
        lock (_lock)
        {
            if (Book.Get(key) is { } entry && entry.QueueId == queueId)
            {
                // Un upgrade fermo torna a UpgradeWatch con il file di prima, un primo download in attesa.
                if (entry.PreviousScore is not null)
                {
                    BackToUpgradeWatch(entry, time.GetUtcNow());
                }
                else
                {
                    BackToWaiting(entry, time.GetUtcNow());
                }
            }
        }
    }

    private DownloadEntry Create(ArrTitle title, DateTimeOffset now)
    {
        var entry = new DownloadEntry
        {
            Key = title.Key,
            Kind = title.Kind,
            State = DownloadStates.Waiting,
            AvailableSince = title.AvailableSince ?? now,
            NextSearchAt = now,
        };
        Describe(entry, title);
        Book.Put(entry);
        return entry;
    }

    // Titolo, poster, profilo e durata possono cambiare in Radarr/Sonarr.
    private static void Describe(DownloadEntry entry, ArrTitle title)
    {
        entry.Title = title.Title;
        entry.PosterUrl = title.PosterUrl;
        entry.ProfileId = title.ProfileId;
        entry.RuntimeMinutes = title.RuntimeMinutes;
        entry.SeriesId = title.SeriesId;
    }

    private static void BackToWaiting(DownloadEntry entry, DateTimeOffset now)
    {
        entry.State = DownloadStates.Waiting;
        entry.Reason = null;
        entry.QueueId = null;
        entry.LastSizeLeft = null;
        entry.LastProgressAt = null;
        entry.NextSearchAt = now;

        // Il file non è arrivato: la scelta non conta più per gli upgrade.
        entry.CurrentScore = null;
        entry.CurrentQualityId = null;
        entry.CurrentSizeBytes = null;
        entry.PreviousScore = null;
        entry.PreviousQualityId = null;
        entry.PreviousSizeBytes = null;
    }

    private static string Key(string kind, int id) => new DownloadKey(kind, id, 0).ToString();

    private static ArrKind ServiceOf(string kind) => kind == DownloadKinds.Movie ? ArrKind.Radarr : ArrKind.Sonarr;

    // Solo il codice, mai il messaggio: può contenere indirizzi o query.
    private static string ErrorOf(Exception ex) => ex is ArrException arrError ? arrError.Error.ToString() : ex.GetType().Name;

    internal static string? Poster(List<ArrImage?>? images) =>
        images?.FirstOrDefault(i => string.Equals(i?.CoverType, "poster", StringComparison.OrdinalIgnoreCase))?.RemoteUrl;

    // Il primo per chiave: un doppione nella risposta non deve far saltare il giro.
    private static Dictionary<TKey, T> ByKey<TKey, T>(IEnumerable<T> items, Func<T, TKey> key)
        where TKey : notnull
    {
        var result = new Dictionary<TKey, T>();
        foreach (var item in items)
        {
            result.TryAdd(key(item), item);
        }

        return result;
    }
}
