using System.Globalization;
using System.Threading.Channels;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// Lo spazio sul seedbox (spec U §6 e §7.3): il calcolo e la panoramica (SpaceService.Scan.cs), tenuti, torrent in
/// attesa di fine seed e le operazioni, una alla volta da una coda (SpaceService.Operations.cs). Stato in <see cref="SpaceBook"/>, su disco con
/// <see cref="SpaceStore"/>. Sicuro tra thread: il libro sta sotto un lock che non resta mai preso durante un'attesa.
/// </summary>
public sealed partial class SpaceService(
    IArrClient arr,
    ISeerrClient seerr,
    ISeerrSettings seerrSettings,
    IQbitClient qbit,
    IFileProbe probe,
    ILibraryRefresh library,
    ISpaceSettings settings,
    SpaceStore store,
    IViewingFacts viewing,
    ISeriesIndex jellyfin,
    RatingService ratings,
    IUserDirectory users,
    TimeProvider time,
    ILogger<SpaceService> logger)
{
    /// <summary>Ogni quanto si controllano i torrent in attesa di fine seed (spec U §6.3).</summary>
    public static readonly TimeSpan PendingInterval = TimeSpan.FromHours(1);

    /// <summary>La chiave di "togli tutti quelli possibili ora" (decisione 11).</summary>
    public const string AllTorrentsKey = "all-torrents";

    private const string TorrentPrefix = "torrent:";

    private readonly Lock _lock = new();
    private readonly Channel<string> _queue = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });

    // Il calcolo su cui è partita ogni operazione in coda; solo sotto _lock.
    private readonly Dictionary<string, SpaceScan> _scanOf = [];
    private SpaceBook? _book;

    /// <summary>L'esito di <see cref="Start"/>.</summary>
    public enum StartOutcome
    {
        Started,

        /// <summary>Tipo sconosciuto o chiave nel formato sbagliato.</summary>
        Invalid,

        /// <summary>La chiave non è nell'ultimo calcolo.</summary>
        Unknown,

        /// <summary>Un'operazione sulla stessa chiave è in coda o in corso.</summary>
        Busy,

        /// <summary>Non c'è ancora un calcolo.</summary>
        NotReady,
    }

    /// <summary>L'ultimo calcolo; null fino al primo.</summary>
    internal SpaceScan? LastScan { get; set; }

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private SpaceBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();

                // Un'operazione in coda o in corso quando il server si è fermato non riparte: risulta fallita e si può ripremere.
                foreach (var operation in _book.Operations.Where(IsActive))
                {
                    Abort(operation);
                }
            }

            return _book;
        }
    }

    /// <summary>
    /// Mette in coda un'operazione (spec U §6.2): controlla tipo e chiave, cerca la chiave nell'ultimo
    /// calcolo, la crea con tutti i passi in attesa e la salva. L'id serve per seguirla.
    /// </summary>
    public (StartOutcome Outcome, string? Id) Start(string kind, string key)
    {
        if (!IsValidKey(kind, key))
        {
            return (StartOutcome.Invalid, null);
        }

        if (LastScan is not { } scan)
        {
            return (StartOutcome.NotReady, null);
        }

        if (TitleOf(scan, kind, key) is not { } title)
        {
            return (StartOutcome.Unknown, null);
        }

        var operation = new SpaceOperation
        {
            Id = Guid.NewGuid().ToString("N"),
            Kind = kind,
            Key = key,
            Title = title,
            State = SpaceOperationStates.Queued,
            StartedAt = time.GetUtcNow(),
            Steps = [.. StepsOf(kind).Select(name => new SpaceStep { Name = name, State = SpaceStepStates.Waiting })],
        };
        lock (_lock)
        {
            if (Book.Operations.Any(o => o.Key == key && IsActive(o)))
            {
                return (StartOutcome.Busy, null);
            }

            Book.AddOperation(operation);
            _scanOf[operation.Id] = scan;
            Save();
        }

        _queue.Writer.TryWrite(operation.Id);
        logger.LogInformation("Spazio: operazione {Kind} su {Key} in coda", kind, LogKey(key));
        return (StartOutcome.Started, operation.Id);
    }

    /// <summary>L'operazione con quell'id; null se non c'è.</summary>
    public SpaceOperationDto? Operation(string id)
    {
        lock (_lock)
        {
            return Book.Operation(id)?.ToDto();
        }
    }

    /// <summary>"Tienilo" (spec U §6.4).</summary>
    public void Keep(string key, string title)
    {
        lock (_lock)
        {
            Book.Keep(key, title);
            Save();
        }
    }

    public void Unkeep(string key)
    {
        lock (_lock)
        {
            Book.Unkeep(key);
            Save();
        }
    }

    /// <summary>Toglie un torrent dall'attesa e lo lascia in qBittorrent (spec U §6.3); falso se non c'era.</summary>
    public bool DropPending(string hash)
    {
        lock (_lock)
        {
            if (!Book.RemovePending(hash))
            {
                return false;
            }

            Save();
            return true;
        }
    }

    /// <summary>Legge il libro sotto il lock: per la panoramica e per i test. Chi lo usa fuori dai test copia quello che gli serve.</summary>
    internal T Read<T>(Func<SpaceBook, T> read)
    {
        lock (_lock)
        {
            return read(Book);
        }
    }

    /// <summary>
    /// Il controllo orario dei torrent in attesa (spec U §6.3): quelli spariti da qBittorrent escono, quelli che la
    /// regola del seed ora permette si tolgono con i file e restano come operazione automatica. Se qBittorrent non
    /// risponde si riprova al giro dopo.
    /// </summary>
    public async Task CheckPendingAsync(CancellationToken cancellationToken)
    {
        List<PendingTorrent> pending;
        lock (_lock)
        {
            pending = [.. Book.Pending];
        }

        if (pending.Count == 0)
        {
            return;
        }

        try
        {
            var live = (await qbit.GetTorrentsAsync(cancellationToken).ConfigureAwait(false))
                .Where(t => t.Hash is not null)
                .DistinctBy(t => t.Hash)
                .ToDictionary(t => t.Hash!);
            foreach (var torrent in pending)
            {
                if (!live.TryGetValue(torrent.Hash, out var now))
                {
                    lock (_lock)
                    {
                        Book.RemovePending(torrent.Hash);
                        Save();
                    }

                    logger.LogInformation("Spazio: il torrent in attesa {Hash} non è più in qBittorrent", Short(torrent.Hash));
                    continue;
                }

                // Il tracker dal vivo; se qBittorrent non ne ha uno attivo, quello salvato.
                var host = SeedRule.HostOf(now.Tracker) is { Length: > 0 } h ? h : torrent.Tracker;
                var facts = new TorrentFacts(torrent.Hash, torrent.Name, host, now.Size, now.Progress, now.Ratio, now.SeedingTime);
                if (SeedRule.Check(facts, settings.Seed, time.GetUtcNow()).CanRemoveNow)
                {
                    await RemovePendingAsync(torrent, cancellationToken).ConfigureAwait(false);
                }
            }
        }
        catch (QbitException ex)
        {
            logger.LogWarning("Spazio: qBittorrent non risponde ({Error}), i torrent in attesa si ricontrollano al prossimo giro", ex.Error);
        }
    }

    private async Task RemovePendingAsync(PendingTorrent torrent, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            // Tolto dall'attesa mentre si leggeva qBittorrent (DropPending): resta in qBittorrent.
            if (!Book.Pending.Any(p => p.Hash == torrent.Hash))
            {
                return;
            }
        }

        var before = ReadQuota();
        await qbit.DeleteAsync([torrent.Hash], cancellationToken).ConfigureAwait(false);
        var after = ReadQuota();
        var now = time.GetUtcNow();
        lock (_lock)
        {
            Book.RemovePending(torrent.Hash);
            Book.AddOperation(new SpaceOperation
            {
                Id = Guid.NewGuid().ToString("N"),
                Kind = SpaceKinds.Torrent,
                Key = TorrentPrefix + torrent.Hash,
                Title = torrent.Title,
                State = SpaceOperationStates.Done,
                Auto = true,
                StartedAt = now,
                EndedAt = now,
                EstimatedFreedBytes = torrent.SizeBytes,
                QuotaBeforeBytes = before?.UsedBytes,
                QuotaAfterBytes = after?.UsedBytes,
                Steps =
                [
                    new SpaceStep { Name = SpaceSteps.RemoveTorrents, State = SpaceStepStates.Done, Done = 1, Waiting = 0 },
                    QuotaStep(after),
                ],
            });
            Save();
        }

        logger.LogInformation("Spazio: torrent {Hash} tolto a fine seed obbligatorio", Short(torrent.Hash));
    }

    /// <summary>
    /// I fatti di un torrent dal vivo (decisione 10): il tracker è il campo <c>tracker</c>; solo se è vuoto si leggono
    /// i tracker del torrent, e se uno è protetto conta quello.
    /// </summary>
    internal async Task<TorrentFacts> FactsAsync(QbitTorrent torrent, CancellationToken cancellationToken)
    {
        var hash = torrent.Hash ?? "";
        var host = SeedRule.HostOf(torrent.Tracker);
        if (host.Length == 0)
        {
            var hosts = (await qbit.GetTrackersAsync(hash, cancellationToken).ConfigureAwait(false))
                .Select(t => SeedRule.HostOf(t.Url))
                .Where(h => h.Length > 0)
                .ToList();
            host = hosts.FirstOrDefault(h => SeedRule.IsProtected(h, settings.Seed.ProtectedDomains)) ?? hosts.FirstOrDefault() ?? "";
        }

        return new TorrentFacts(hash, torrent.Name ?? "", host, torrent.Size, torrent.Progress, torrent.Ratio, torrent.SeedingTime);
    }

    /// <summary>La quota dal file del cron; null se non è configurato o non si legge.</summary>
    private Quota? ReadQuota() =>
        string.IsNullOrWhiteSpace(settings.QuotaFile) ? null : QuotaFile.Parse(probe.ReadText(settings.QuotaFile));

    private SpaceStep QuotaStep(Quota? quota) => quota is not null
        ? new SpaceStep { Name = SpaceSteps.ReadQuota, State = SpaceStepStates.Done }
        : new SpaceStep
        {
            Name = SpaceSteps.ReadQuota,
            State = SpaceStepStates.Skipped,
            Detail = string.IsNullOrWhiteSpace(settings.QuotaFile) ? SpaceDetails.NotConfigured : SpaceDetails.Unreachable,
        };

    // Solo sotto _lock. Un disco che non scrive non deve fermare un'operazione a metà: lo stato resta in memoria.
    private void Save()
    {
        Book.Prune(time.GetUtcNow());
        try
        {
            store.Save(Book);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning("Spazio: non riesco a salvare il file ({Error})", ex.GetType().Name);
        }
    }

    private static bool IsActive(SpaceOperation operation) =>
        operation.State is SpaceOperationStates.Queued or SpaceOperationStates.Running;

    // Fallita: il passo in corso fallisce, quelli in attesa restano non fatti.
    private void Abort(SpaceOperation operation)
    {
        foreach (var step in operation.Steps)
        {
            if (step.State == SpaceStepStates.Running)
            {
                step.State = SpaceStepStates.Failed;
                step.Detail = SpaceDetails.Failed;
            }
            else if (step.State == SpaceStepStates.Waiting)
            {
                step.State = SpaceStepStates.NotDone;
            }
        }

        operation.State = SpaceOperationStates.Failed;
        operation.EndedAt = time.GetUtcNow();
    }

    /// <summary>Il formato della chiave per il tipo (decisione 11).</summary>
    internal static bool IsValidKey(string kind, string key)
    {
        var parts = key.Split(':');
        return kind switch
        {
            SpaceKinds.Movie => parts is ["movie", var id] && IsId(id),
            SpaceKinds.Series => parts is ["series", var id] && IsId(id),
            SpaceKinds.Season => parts is ["season", var id, var season] && IsId(id)
                && int.TryParse(season, NumberStyles.None, CultureInfo.InvariantCulture, out _),
            SpaceKinds.Torrent => parts is ["torrent", { Length: > 0 } hash] && hash.All(char.IsAsciiLetterOrDigit),
            SpaceKinds.AllTorrents => key == AllTorrentsKey,
            SpaceKinds.Orphan or SpaceKinds.Duplicate => parts is ["file", { Length: 16 } h] && h.All(char.IsAsciiHexDigitLower),
            _ => false,
        };
    }

    private static bool IsId(string text) =>
        int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0;

    /// <summary>Il titolo dell'operazione dal calcolo; null se la chiave non c'è (o un file è dell'altro tipo).</summary>
    private static string? TitleOf(SpaceScan scan, string kind, string key) => kind switch
    {
        SpaceKinds.Movie or SpaceKinds.Series or SpaceKinds.Season => scan.Titles.GetValueOrDefault(key)?.Title,
        SpaceKinds.Torrent => scan.Torrents.GetValueOrDefault(key[TorrentPrefix.Length..])?.Name,
        SpaceKinds.AllTorrents => "",
        _ => scan.Files.TryGetValue(key, out var file) && file.Kind == kind ? file.Path[(file.Path.LastIndexOf('/') + 1)..] : null,
    };

    /// <summary>La chiave per il registro: di un torrent solo i primi 8 caratteri dell'hash.</summary>
    private static string LogKey(string key) =>
        key.StartsWith(TorrentPrefix, StringComparison.Ordinal) ? TorrentPrefix + Short(key[TorrentPrefix.Length..]) : key;

    private static string Short(string hash) => hash[..Math.Min(8, hash.Length)];
}
