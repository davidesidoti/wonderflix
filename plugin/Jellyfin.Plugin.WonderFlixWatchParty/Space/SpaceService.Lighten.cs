using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Lo <c>State</c> del download di un "Alleggerisci", come nei DTO (piano 30d).</summary>
public static class SpaceLightenStates
{
    public const string Downloading = "Downloading";

    public const string Importing = "Importing";

    public const string Failed = "Failed";

    /// <summary>Scaricato, ma Radarr/Sonarr non lo importano da soli (<c>importBlocked</c>).</summary>
    public const string Blocked = "Blocked";
}

/// <summary>Lo stato dei download di "Alleggerisci" sulle righe di Alleggerire (piano 30d, Global Constraints).</summary>
public sealed partial class SpaceService
{
    /// <summary>Un grab di "Alleggerisci" si dimentica dopo così tanto.</summary>
    public static readonly TimeSpan LightenRetention = TimeSpan.FromDays(7);

    /// <summary>Il tempo che Radarr/Sonarr mettano in coda un grab appena fatto.</summary>
    public static readonly TimeSpan LightenQueueGrace = TimeSpan.FromMinutes(10);

    /// <summary>Dopo un import a mano, per così tanto un Blocked si mostra come Importing: il comando non è ancora finito.</summary>
    public static readonly TimeSpan HandImportGrace = TimeSpan.FromMinutes(2);

    /// <summary>Senza date, sotto questa parte della riga il file nuovo è arrivato.</summary>
    private const double ImportedShare = 0.9;

    // Solo sotto _lock. L'ultimo stato letto per chiave: resta se un servizio non risponde.
    private readonly Dictionary<string, SpaceLightenDownloadDto> _lightenStatus = [];

    // Solo sotto _lock. Le righe importate e quando: nascoste fino al calcolo dopo.
    private readonly Dictionary<string, DateTimeOffset> _lightenImported = [];

    // Solo sotto _lock. Gli import a mano riusciti e quando: per HandImportGrace un Blocked è Importing.
    private readonly Dictionary<string, DateTimeOffset> _lightenHandImported = [];

    // Solo sotto _lock. I servizi la cui coda non risponde: il Warning una volta per guasto.
    private readonly HashSet<ArrKind> _queueDown = [];

    /// <summary>
    /// Le righe con il loro download di "Alleggerisci", senza quelle già importate. Una lettura della coda per servizio,
    /// solo se una riga ha un grab; il file attuale solo per le righe fuori dalla coda.
    /// </summary>
    private async Task<List<SpaceLightenDto>> WithDownloadsAsync(IReadOnlyList<SpaceLightenDto> rows, DateTimeOffset? scannedAt, CancellationToken ct)
    {
        var now = time.GetUtcNow();
        var marked = new Dictionary<string, DateTimeOffset>();
        foreach (var (key, at) in downloads.LightenedKeys())
        {
            if (now - at <= LightenRetention)
            {
                marked[key] = at;
                continue;
            }

            downloads.ForgetLightened(key);
            lock (_lock)
            {
                _lightenStatus.Remove(key);
                _lightenHandImported.Remove(key);
            }

            logger.LogInformation("Spazio: Alleggerisci {Key} dimenticato dopo 7 giorni", key);
        }

        var tracked = rows.Where(r => marked.ContainsKey(r.Key)).ToList();
        var radarr = tracked.Any(r => r.Kind == SpaceKinds.Movie) ? await QueueAsync(ArrKind.Radarr, ct).ConfigureAwait(false) : null;
        var sonarr = tracked.Any(r => r.Kind == SpaceKinds.Season) ? await QueueAsync(ArrKind.Sonarr, ct).ConfigureAwait(false) : null;
        var statuses = new Dictionary<string, SpaceLightenDownloadDto?>();
        foreach (var row in tracked)
        {
            var queue = row.Kind == SpaceKinds.Movie ? radarr : sonarr;
            var (imported, status) = queue is null
                ? (false, CachedStatus(row.Key))
                : await StatusAsync(row, marked[row.Key], queue, now, ct).ConfigureAwait(false);
            if (imported)
            {
                downloads.ForgetLightened(row.Key);
                logger.LogInformation("Spazio: Alleggerisci {Key} importato", row.Key);
            }

            lock (_lock)
            {
                if (imported)
                {
                    _lightenImported[row.Key] = now;
                    _lightenStatus.Remove(row.Key);
                    _lightenHandImported.Remove(row.Key);
                }
                else if (status is not null)
                {
                    // Subito dopo l'import a mano Radarr/Sonarr dicono ancora importBlocked; passata la finestra, il blocco è vero.
                    if (status.State == SpaceLightenStates.Blocked && _lightenHandImported.TryGetValue(row.Key, out var handAt) && now - handAt < HandImportGrace)
                    {
                        status = status with { State = SpaceLightenStates.Importing, Message = null };
                    }

                    _lightenStatus[row.Key] = status;
                }
            }

            statuses[row.Key] = status;
        }

        lock (_lock)
        {
            // Quelle di prima del calcolo non servono più: il calcolo ha letto il file nuovo.
            foreach (var key in _lightenImported.Where(p => scannedAt >= p.Value).Select(p => p.Key).ToList())
            {
                _lightenImported.Remove(key);
            }

            return [.. rows.Where(r => !_lightenImported.ContainsKey(r.Key)).Select(r => r with { Download = statuses.GetValueOrDefault(r.Key) })];
        }
    }

    /// <summary>L'esito di <see cref="ImportLightenAsync"/>.</summary>
    public enum LightenImportOutcome
    {
        Imported,

        /// <summary>Chiave sbagliata, nessun "Alleggerisci" ricordato o niente di bloccato in coda.</summary>
        Unknown,

        /// <summary>La coda non si legge o un import non parte: <c>Error</c> è il codice.</summary>
        Failed,
    }

    /// <summary>
    /// Importa a mano i download bloccati (<c>importBlocked</c>) di un "Alleggerisci": un import per download. Se riesce la
    /// riga passa a Importing.
    /// </summary>
    public async Task<(LightenImportOutcome Outcome, string? Error)> ImportLightenAsync(string key, CancellationToken ct)
    {
        var kind = IsValidKey(SpaceKinds.Movie, key) ? ArrKind.Radarr : IsValidKey(SpaceKinds.Season, key) ? ArrKind.Sonarr : (ArrKind?)null;
        if (kind is not { } service || !downloads.LightenedKeys().ContainsKey(key))
        {
            return (LightenImportOutcome.Unknown, null);
        }

        List<ArrQueueItem> queue;
        try
        {
            queue = [.. (await arr.GetQueueAsync(service, ct).ConfigureAwait(false)).OfType<ArrQueueItem>()];
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Spazio: Alleggerisci {Key}, la coda di {Service} non si legge ({Error})", key, service, UpcomingErrors.Code(ex.Error));
            return (LightenImportOutcome.Failed, UpcomingErrors.Code(ex.Error));
        }

        var blocked = ItemsOf(key, queue)
            .Where(i => string.Equals(i.TrackedDownloadState, "importBlocked", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(i.DownloadId))
            .Select(i => i.DownloadId!)
            .Distinct()
            .ToList();
        if (blocked.Count == 0)
        {
            return (LightenImportOutcome.Unknown, null);
        }

        string? error = null;
        foreach (var downloadId in blocked)
        {
            var result = await downloads.ImportDownloadAsync(service, downloadId, ct).ConfigureAwait(false);
            error ??= result;
        }

        if (error is not null)
        {
            logger.LogWarning("Spazio: Alleggerisci {Key} non importato a mano ({Error})", key, error);
            return (LightenImportOutcome.Failed, error);
        }

        lock (_lock)
        {
            // Il download è finito: fino alla prossima lettura della coda la riga è Importing.
            _lightenStatus[key] = new SpaceLightenDownloadDto(SpaceLightenStates.Importing, 1, 0, null);
            _lightenHandImported[key] = time.GetUtcNow();
        }

        logger.LogInformation("Spazio: Alleggerisci {Key} importato a mano", key);
        return (LightenImportOutcome.Imported, null);
    }

    /// <summary>La coda del servizio; null se non risponde.</summary>
    private async Task<IReadOnlyList<ArrQueueItem>?> QueueAsync(ArrKind kind, CancellationToken ct)
    {
        try
        {
            var queue = (await arr.GetQueueAsync(kind, ct).ConfigureAwait(false)).OfType<ArrQueueItem>().ToList();
            lock (_lock)
            {
                _queueDown.Remove(kind);
            }

            return queue;
        }
        catch (ArrException ex)
        {
            bool first;
            lock (_lock)
            {
                first = _queueDown.Add(kind);
            }

            if (first)
            {
                logger.LogWarning("Spazio: {Service} non risponde ({Error}), lo stato di Alleggerisci resta quello di prima", kind, UpcomingErrors.Code(ex.Error));
            }

            return null;
        }
    }

    // Lo stato di una riga con un grab; Imported se il file nuovo è arrivato.
    private async Task<(bool Imported, SpaceLightenDownloadDto? Status)> StatusAsync(
        SpaceLightenDto row, DateTimeOffset grabbedAt, IReadOnlyList<ArrQueueItem> queue, DateTimeOffset now, CancellationToken ct)
    {
        var (id, season) = IdsOf(row.Key);
        var items = ItemsOf(row.Key, queue);
        if (items.Count > 0)
        {
            return (false, FromQueue(items));
        }

        List<(long Size, DateTimeOffset? Added)> files;
        try
        {
            files = season is { } n
                ? [.. (await arr.GetEpisodeFilesAsync(id, ct).ConfigureAwait(false)).OfType<ArrFile>().Where(f => f.SeasonNumber == n).Select(f => (f.Size, f.DateAdded))]
                : (await arr.GetMovieAsync(id, ct).ConfigureAwait(false)).MovieFile is { } file ? [(file.Size, file.DateAdded)] : [];
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Spazio: il file di {Key} non si legge ({Error}), lo stato di Alleggerisci resta quello di prima", row.Key, UpcomingErrors.Code(ex.Error));
            return (false, CachedStatus(row.Key));
        }

        // Importato = un file aggiunto dopo il grab; senza date, un file molto più leggero.
        var imported = files.Any(f => f.Added > grabbedAt)
            || (!(files.Count > 0 && files.All(f => f.Added is not null)) && files.Sum(f => f.Size) < ImportedShare * row.SizeBytes);
        if (imported)
        {
            return (true, null);
        }

        return (false, new SpaceLightenDownloadDto(now - grabbedAt < LightenQueueGrace ? SpaceLightenStates.Downloading : SpaceLightenStates.Failed, 0, 0, null));
    }

    // Il film o la serie e la stagione di una chiave "movie:ID" o "season:ID:N".
    private static (int Id, int? Season) IdsOf(string key)
    {
        var parts = key.Split(':');
        return (int.Parse(parts[1], CultureInfo.InvariantCulture), parts.Length == 3 ? int.Parse(parts[2], CultureInfo.InvariantCulture) : null);
    }

    // Le voci della coda di una riga: quelle del film, o degli episodi della stagione.
    private static List<ArrQueueItem> ItemsOf(string key, IEnumerable<ArrQueueItem> queue)
    {
        var (id, season) = IdsOf(key);
        return [.. queue.Where(q => season is { } n ? q.SeriesId == id && q.SeasonNumber == n : q.MovieId == id)];
    }

    // Una stagione può avere più voci (episodi singoli): scarica finché una scarica, il progresso è quello di tutte.
    // Un pack dà una voce per episodio con il peso di tutto il download: si conta una volta per download.
    private static SpaceLightenDownloadDto FromQueue(IReadOnlyList<ArrQueueItem> items)
    {
        // Senza DownloadId ogni voce è un download a sé (come contarla per Id).
        var downloads = items.Where(i => i.DownloadId is null).Concat(items.Where(i => i.DownloadId is not null).DistinctBy(i => i.DownloadId)).ToList();
        var size = downloads.Sum(i => i.Size);
        var left = downloads.Sum(i => i.Sizeleft);
        var progress = size > 0 ? Math.Round(Math.Clamp(1 - ((double)left / size), 0, 1), 2) : 0;
        var blocked = items.Where(i => Is(i, "importBlocked")).ToList();
        var state = items.Any(i => Is(i, "downloading")) ? SpaceLightenStates.Downloading
            : blocked.Count > 0 ? SpaceLightenStates.Blocked
            : items.Any(i => Is(i, "failed") || Is(i, "failedPending")) ? SpaceLightenStates.Failed
            : SpaceLightenStates.Importing;

        // Il perché del blocco, per l'admin: i primi tre messaggi diversi.
        var messages = state == SpaceLightenStates.Blocked
            ? blocked.SelectMany(i => i.StatusMessages ?? []).SelectMany(m => m?.Messages ?? []).Where(m => !string.IsNullOrWhiteSpace(m)).Distinct().Take(3).ToList()
            : [];
        return new SpaceLightenDownloadDto(state, progress, left, messages.Count > 0 ? string.Join('\n', messages) : null);

        static bool Is(ArrQueueItem item, string state) => string.Equals(item.TrackedDownloadState, state, StringComparison.OrdinalIgnoreCase);
    }

    private SpaceLightenDownloadDto? CachedStatus(string key)
    {
        lock (_lock)
        {
            return _lightenStatus.GetValueOrDefault(key);
        }
    }
}
