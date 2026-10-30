using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Il <c>Kind</c> di un'operazione, come nei DTO (spec U §6.2).</summary>
public static class SpaceKinds
{
    public const string Movie = "Movie";

    public const string Series = "Series";

    public const string Season = "Season";

    public const string Torrent = "Torrent";

    public const string AllTorrents = "AllTorrents";

    public const string Orphan = "Orphan";

    public const string Duplicate = "Duplicate";
}

/// <summary>Lo <c>State</c> di un'operazione, come nei DTO (spec U §6.1).</summary>
public static class SpaceOperationStates
{
    public const string Queued = "Queued";

    public const string Running = "Running";

    public const string Done = "Done";

    public const string Failed = "Failed";
}

/// <summary>Lo <c>State</c> di un passo, come nei DTO (spec U §6.1).</summary>
public static class SpaceStepStates
{
    public const string Waiting = "Waiting";

    public const string Running = "Running";

    public const string Done = "Done";

    public const string Skipped = "Skipped";

    public const string Failed = "Failed";

    /// <summary>Non fatto perché un passo prima è fallito.</summary>
    public const string NotDone = "NotDone";
}

/// <summary>Il <c>Name</c> di un passo, come nei DTO (spec U §6.2).</summary>
public static class SpaceSteps
{
    public const string FindTorrents = "FindTorrents";

    public const string RemoveFromQueue = "RemoveFromQueue";

    public const string DeleteFromRadarr = "DeleteFromRadarr";

    public const string DeleteFromSonarr = "DeleteFromSonarr";

    public const string UnmonitorSeason = "UnmonitorSeason";

    public const string DeleteEpisodeFiles = "DeleteEpisodeFiles";

    public const string RemoveTorrents = "RemoveTorrents";

    public const string RemoveFromSeerr = "RemoveFromSeerr";

    public const string RefreshLibrary = "RefreshLibrary";

    public const string DeleteFile = "DeleteFile";

    public const string ReadQuota = "ReadQuota";
}

/// <summary>Il <c>Detail</c> di un passo saltato o fallito, come nei DTO (spec U §6.5).</summary>
public static class SpaceDetails
{
    public const string NotConfigured = "NotConfigured";

    public const string Unauthorized = "Unauthorized";

    public const string Unreachable = "Unreachable";

    /// <summary>Il titolo, il torrent o il media non c'è più (un 404): si va avanti.</summary>
    public const string Gone = "Gone";

    /// <summary>Il torrent è ancora in seed obbligatorio.</summary>
    public const string SeedRule = "SeedRule";

    public const string Failed = "Failed";
}

/// <summary>Un titolo tenuto con "Tienilo" (spec U §6.4).</summary>
public sealed class KeptTitle
{
    public string Key { get; set; } = "";

    public string Title { get; set; } = "";
}

/// <summary>Un torrent in attesa di fine seed obbligatorio (spec U §6.3). <c>Tracker</c> è l'host.</summary>
public sealed class PendingTorrent
{
    public string Hash { get; set; } = "";

    public string Name { get; set; } = "";

    public string Tracker { get; set; } = "";

    public long SizeBytes { get; set; }

    /// <summary>Quando scade il seed obbligatorio; null se non si può prevedere (ancora in download).</summary>
    public DateTimeOffset? ExpectedAt { get; set; }

    /// <summary>Il titolo cancellato con cui il torrent doveva andare via.</summary>
    public string Title { get; set; } = "";
}

/// <summary>Un passo di un'operazione (spec U §6.1), come <see cref="SpaceStepDto"/>.</summary>
public sealed class SpaceStep
{
    public string Name { get; set; } = "";

    public string State { get; set; } = "";

    public string? Detail { get; set; }

    public int? Done { get; set; }

    public int? Waiting { get; set; }
}

/// <summary>Un'operazione dello spazio (spec U §6.1), come <see cref="SpaceOperationDto"/>.</summary>
public sealed class SpaceOperation
{
    public string Id { get; set; } = "";

    public string Kind { get; set; } = "";

    public string Key { get; set; } = "";

    public string Title { get; set; } = "";

    public string State { get; set; } = "";

    /// <summary>Vero per i torrent tolti dal controllo orario a fine seed.</summary>
    public bool Auto { get; set; }

    public DateTimeOffset StartedAt { get; set; }

    public DateTimeOffset? EndedAt { get; set; }

    public long EstimatedFreedBytes { get; set; }

    public long PendingBytes { get; set; }

    public long? QuotaBeforeBytes { get; set; }

    public long? QuotaAfterBytes { get; set; }

    /// <summary>Gli hash che un'operazione della Pulizia ha tolto davvero: la panoramica li nasconde fino al calcolo dopo (spec U §6.1).</summary>
    public List<string> RemovedHashes { get; set; } = [];

    public List<SpaceStep> Steps { get; set; } = [];

    public SpaceOperationDto ToDto() => new(
        Id, Kind, Key, Title, State, Auto, StartedAt, EndedAt, EstimatedFreedBytes, PendingBytes, QuotaBeforeBytes, QuotaAfterBytes,
        [.. Steps.Select(s => new SpaceStepDto(s.Name, s.State, s.Detail, s.Done, s.Waiting))]);
}

/// <summary><c>space.json</c> (spec U §7.3): tenuti, torrent in attesa e operazioni, dalla più recente.</summary>
public sealed class SpaceFile
{
    public const int CurrentVersion = 1;

    public int Version { get; set; } = CurrentVersion;

    public List<KeptTitle> Kept { get; set; } = [];

    public List<PendingTorrent> Pending { get; set; } = [];

    public List<SpaceOperation> Operations { get; set; } = [];
}

/// <summary>
/// I dati dello spazio in memoria (spec U §6.3, §6.4 e §7.3). Non è sicuro tra thread:
/// lo usa solo <see cref="SpaceService"/>, sotto il suo lock.
/// </summary>
public sealed class SpaceBook
{
    /// <summary>Le operazioni si conservano 30 giorni (spec U §6.1).</summary>
    public static readonly TimeSpan OperationRetention = TimeSpan.FromDays(30);

    private readonly List<KeptTitle> _kept = [];
    private readonly List<PendingTorrent> _pending = [];

    // Dalla più recente.
    private readonly List<SpaceOperation> _operations = [];

    public IReadOnlyList<KeptTitle> Kept => _kept;

    public IReadOnlyList<PendingTorrent> Pending => _pending;

    /// <summary>Dalla più recente.</summary>
    public IReadOnlyList<SpaceOperation> Operations => _operations;

    /// <summary>Tiene il titolo; se c'è già ne aggiorna il nome.</summary>
    public void Keep(string key, string title)
    {
        Unkeep(key);
        _kept.Add(new KeptTitle { Key = key, Title = title });
    }

    public void Unkeep(string key) => _kept.RemoveAll(k => k.Key == key);

    public bool IsKept(string key) => _kept.Exists(k => k.Key == key);

    /// <summary>Aggiunge il torrent in attesa; uno con lo stesso hash resta com'è.</summary>
    public void AddPending(PendingTorrent torrent)
    {
        if (!_pending.Exists(p => p.Hash == torrent.Hash))
        {
            _pending.Add(torrent);
        }
    }

    /// <summary>Falso se il torrent non era in attesa.</summary>
    public bool RemovePending(string hash) => _pending.RemoveAll(p => p.Hash == hash) > 0;

    public void AddOperation(SpaceOperation operation) => _operations.Insert(0, operation);

    public SpaceOperation? Operation(string id) => _operations.Find(o => o.Id == id);

    /// <summary>Toglie le operazioni finite (o iniziate) da più di <see cref="OperationRetention"/>.</summary>
    public void Prune(DateTimeOffset now) =>
        _operations.RemoveAll(o => (o.EndedAt ?? o.StartedAt) < now - OperationRetention);

    /// <exception cref="FormatException">Versione diversa, un elenco null o con voci null, o un campo di testo null.</exception>
    public static SpaceBook FromFile(SpaceFile file)
    {
        if (file.Version != SpaceFile.CurrentVersion)
        {
            throw new FormatException("versione sconosciuta");
        }

        // Il JSON può mettere null anche dove il tipo non lo ammette: un file così è rovinato.
        var book = new SpaceBook();
        book._kept.AddRange(Required(file.Kept, k => [k.Key, k.Title]));
        book._pending.AddRange(Required(file.Pending, p => [p.Hash, p.Name, p.Tracker, p.Title]));
        foreach (var operation in Required(file.Operations, o => [o.Id, o.Kind, o.Key, o.Title, o.State]))
        {
            Required(operation.Steps, s => [s.Name, s.State]);
            book._operations.Add(operation);
        }

        return book;
    }

    public SpaceFile ToFile() => new()
    {
        Kept = [.. _kept],
        Pending = [.. _pending],
        Operations = [.. _operations],
    };

    private static List<T> Required<T>(List<T>? list, Func<T, string?[]> texts) =>
        list is null || list.Exists(item => item is null || texts(item).Contains(null))
            ? throw new FormatException("elenco, voce o campo null")
            : list;
}
