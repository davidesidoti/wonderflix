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
}

/// <summary>Lo stato dei download di "Alleggerisci" sulle righe di Alleggerire (piano 30d, Global Constraints).</summary>
public sealed partial class SpaceService
{
    /// <summary>Un grab di "Alleggerisci" si dimentica dopo così tanto.</summary>
    public static readonly TimeSpan LightenRetention = TimeSpan.FromDays(7);

    /// <summary>Il tempo che Radarr/Sonarr mettano in coda un grab appena fatto.</summary>
    public static readonly TimeSpan LightenQueueGrace = TimeSpan.FromMinutes(10);

    /// <summary>Sotto questa parte della riga il file nuovo è arrivato.</summary>
    private const double ImportedShare = 0.9;

    // Solo sotto _lock. L'ultimo stato letto per chiave: resta se un servizio non risponde.
    private readonly Dictionary<string, SpaceLightenDownloadDto> _lightenStatus = [];

    // Solo sotto _lock. Le righe importate e quando: nascoste fino al calcolo dopo.
    private readonly Dictionary<string, DateTimeOffset> _lightenImported = [];

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
                }
                else if (status is not null)
                {
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

    /// <summary>La coda del servizio; null se non risponde.</summary>
    private async Task<IReadOnlyList<ArrQueueItem>?> QueueAsync(ArrKind kind, CancellationToken ct)
    {
        try
        {
            return [.. (await arr.GetQueueAsync(kind, ct).ConfigureAwait(false)).OfType<ArrQueueItem>()];
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Spazio: {Service} non risponde ({Error}), lo stato di Alleggerisci resta quello di prima", kind, UpcomingErrors.Code(ex.Error));
            return null;
        }
    }

    // Lo stato di una riga con un grab; Imported se il file nuovo è arrivato.
    private async Task<(bool Imported, SpaceLightenDownloadDto? Status)> StatusAsync(
        SpaceLightenDto row, DateTimeOffset grabbedAt, IReadOnlyList<ArrQueueItem> queue, DateTimeOffset now, CancellationToken ct)
    {
        var parts = row.Key.Split(':');
        var id = int.Parse(parts[1], CultureInfo.InvariantCulture);
        int? season = parts.Length == 3 ? int.Parse(parts[2], CultureInfo.InvariantCulture) : null;
        var items = queue.Where(q => season is { } n ? q.SeriesId == id && q.SeasonNumber == n : q.MovieId == id).ToList();
        if (items.Count > 0)
        {
            return (false, FromQueue(items));
        }

        long current;
        try
        {
            current = season is { } n
                ? (await arr.GetEpisodeFilesAsync(id, ct).ConfigureAwait(false)).OfType<ArrFile>().Where(f => f.SeasonNumber == n).Sum(f => f.Size)
                : (await arr.GetMovieAsync(id, ct).ConfigureAwait(false)).MovieFile?.Size ?? 0;
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Spazio: il file di {Key} non si legge ({Error}), lo stato di Alleggerisci resta quello di prima", row.Key, UpcomingErrors.Code(ex.Error));
            return (false, CachedStatus(row.Key));
        }

        if (current < ImportedShare * row.SizeBytes)
        {
            return (true, null);
        }

        return (false, new SpaceLightenDownloadDto(now - grabbedAt < LightenQueueGrace ? SpaceLightenStates.Downloading : SpaceLightenStates.Failed, 0, 0));
    }

    // Una stagione può avere più voci (episodi singoli): scarica finché una scarica, il progresso è quello di tutte.
    private static SpaceLightenDownloadDto FromQueue(IReadOnlyList<ArrQueueItem> items)
    {
        var size = items.Sum(i => i.Size);
        var left = items.Sum(i => i.Sizeleft);
        var progress = size > 0 ? Math.Round(Math.Clamp(1 - ((double)left / size), 0, 1), 2) : 0;
        var state = items.Any(i => Is(i, "downloading")) ? SpaceLightenStates.Downloading
            : items.Any(i => Is(i, "failed") || Is(i, "failedPending")) ? SpaceLightenStates.Failed
            : SpaceLightenStates.Importing;
        return new SpaceLightenDownloadDto(state, progress, left);

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
