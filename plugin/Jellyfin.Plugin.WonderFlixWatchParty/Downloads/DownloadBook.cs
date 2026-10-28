namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Il <c>Kind</c> di una voce, come nei DTO (spec T §3).</summary>
public static class DownloadKinds
{
    public const string Movie = "Movie";

    public const string Episode = "Episode";

    public const string Season = "Season";
}

/// <summary>Lo <c>State</c> di una voce, come nei DTO (spec T §3).</summary>
public static class DownloadStates
{
    public const string Waiting = "Waiting";

    public const string Downloading = "Downloading";

    public const string UpgradeWatch = "UpgradeWatch";

    public const string NeedsYou = "NeedsYou";
}

/// <summary>La <c>Reason</c> di una voce, come nei DTO (spec T §3); null se non serve.</summary>
public static class DownloadReasons
{
    public const string NothingFound = "NothingFound";

    public const string BelowMinScore = "BelowMinScore";

    public const string ImportBlocked = "ImportBlocked";

    public const string SearchFailed = "SearchFailed";
}

/// <summary>Un titolo che manca o che si tiene d'occhio (spec T §3). Serializzato così com'è; <c>Kind</c> e <c>State</c> sono stringhe come nei DTO.</summary>
public sealed class DownloadEntry
{
    /// <summary><c>movie:12</c>, <c>episode:34</c>, <c>season:5:2</c>.</summary>
    public string Key { get; set; } = "";

    /// <summary><c>Movie</c>, <c>Episode</c> o <c>Season</c>.</summary>
    public string Kind { get; set; } = "";

    public string Title { get; set; } = "";

    public string? PosterUrl { get; set; }

    /// <summary><c>Waiting</c>, <c>Downloading</c>, <c>UpgradeWatch</c> o <c>NeedsYou</c>.</summary>
    public string State { get; set; } = "";

    /// <summary><c>NothingFound</c>, <c>BelowMinScore</c>, <c>ImportBlocked</c>, <c>SearchFailed</c> o null.</summary>
    public string? Reason { get; set; }

    public DateTimeOffset AvailableSince { get; set; }

    public DateTimeOffset? LastSearchAt { get; set; }

    public DateTimeOffset? NextSearchAt { get; set; }

    public DateTimeOffset? UpgradeUntil { get; set; }

    public int? QueueId { get; set; }

    public long? LastSizeLeft { get; set; }

    public DateTimeOffset? LastProgressAt { get; set; }

    public int? CurrentScore { get; set; }

    public int? CurrentQualityId { get; set; }

    /// <summary>Peso della scelta mentre scarica, poi del file arrivato.</summary>
    public long? CurrentSizeBytes { get; set; }

    /// <summary>Durante il download di un upgrade: punteggio, qualità e peso del file di prima (null per un primo download).</summary>
    public int? PreviousScore { get; set; }

    public int? PreviousQualityId { get; set; }

    public long? PreviousSizeBytes { get; set; }

    /// <summary>Solo Sonarr: la serie dell'episodio, per rileggere il suo file.</summary>
    public int SeriesId { get; set; }

    public bool ManualImportPending { get; set; }

    public int ProfileId { get; set; }

    /// <summary>Il nome del profilo all'ultima scelta: serve all'obiettivo quando il file arriva.</summary>
    public string? ProfileName { get; set; }

    public int RuntimeMinutes { get; set; }
}

/// <summary>Una scelta fatta (spec T §3): i campi della release sono piatti, come in <c>DownloadChoiceDto</c>.</summary>
public sealed class DownloadChoice
{
    public string Guid { get; set; } = "";

    public int IndexerId { get; set; }

    public string Indexer { get; set; } = "";

    public string ReleaseTitle { get; set; } = "";

    public string Quality { get; set; } = "";

    public int QualityId { get; set; }

    public int Resolution { get; set; }

    public long SizeBytes { get; set; }

    public int Score { get; set; }

    public int? Seeders { get; set; }

    public string Key { get; set; } = "";

    public string Kind { get; set; } = "";

    public string Title { get; set; } = "";

    public string? PosterUrl { get; set; }

    public DateTimeOffset At { get; set; }

    public long? PreviousSizeBytes { get; set; }

    public int? PreviousScore { get; set; }

    public bool ByAdmin { get; set; }
}

/// <summary>Un titolo dell'elenco da ripassare (spec T §6), come in <c>ReviewItemDto</c>.</summary>
public sealed class ReviewItem
{
    public string Key { get; set; } = "";

    public string Kind { get; set; } = "";

    public string Title { get; set; } = "";

    public string? PosterUrl { get; set; }

    public int Score { get; set; }

    public long SizeBytes { get; set; }

    public string Quality { get; set; } = "";
}

/// <summary>Contenuto di downloads.json (spec T §3).</summary>
public sealed class DownloadFile
{
    public const int CurrentVersion = 1;

    public int Version { get; set; } = CurrentVersion;

    public List<DownloadEntry> Entries { get; set; } = [];

    public List<DownloadChoice> Choices { get; set; } = [];

    public List<ReviewItem> Review { get; set; } = [];

    public DateTimeOffset? ReviewAt { get; set; }

    public List<string> Accepted { get; set; } = [];
}

/// <summary>
/// Lo stato dei download in memoria (spec T §3). Non è sicuro tra thread: lo
/// usa solo DownloadService, sotto lock.
/// </summary>
public sealed class DownloadBook
{
    /// <summary>Le scelte si ricordano per così tanto tempo.</summary>
    public static readonly TimeSpan ChoiceRetention = TimeSpan.FromDays(90);

    private readonly Dictionary<string, DownloadEntry> _entries = [];
    private readonly List<DownloadChoice> _choices = [];
    private readonly HashSet<string> _accepted = [];
    private List<ReviewItem> _review = [];

    public IReadOnlyList<DownloadEntry> Entries => [.. _entries.Values];

    /// <summary>Dalla più recente.</summary>
    public IReadOnlyList<DownloadChoice> Choices => [.. _choices.OrderByDescending(c => c.At)];

    public IReadOnlyList<ReviewItem> Review => [.. _review];

    public DateTimeOffset? ReviewAt { get; private set; }

    public DownloadEntry? Get(string key) => _entries.GetValueOrDefault(key);

    /// <summary>Aggiunge la voce o sostituisce quella con la stessa chiave.</summary>
    public void Put(DownloadEntry entry) => _entries[entry.Key] = entry;

    public bool Remove(string key) => _entries.Remove(key);

    public void AddChoice(DownloadChoice choice) => _choices.Add(choice);

    /// <summary>Toglie le scelte più vecchie di <see cref="ChoiceRetention"/>; restituisce quante.</summary>
    public int Prune(DateTimeOffset now) => _choices.RemoveAll(c => c.At < now - ChoiceRetention);

    public void SetReview(IReadOnlyList<ReviewItem> items, DateTimeOffset at)
    {
        _review = [.. items];
        ReviewAt = at;
    }

    /// <summary>"Va bene così": ricorda la chiave e la toglie dall'elenco; true se è cambiato qualcosa.</summary>
    public bool Accept(string key)
    {
        var added = _accepted.Add(key);
        var removed = _review.RemoveAll(r => r.Key == key) > 0;
        return added || removed;
    }

    public bool IsAccepted(string key) => _accepted.Contains(key);

    /// <summary>Legge il file; <see cref="FormatException"/> per una versione diversa da 1, un elenco null o una voce null.</summary>
    public static DownloadBook FromFile(DownloadFile file)
    {
        if (file.Version != DownloadFile.CurrentVersion)
        {
            throw new FormatException("versione sconosciuta");
        }

        var book = new DownloadBook();
        foreach (var entry in Required(file.Entries))
        {
            // La chiave indicizza il dizionario: una voce senza chiave è un file rovinato.
            if (string.IsNullOrEmpty(entry.Key))
            {
                throw new FormatException("voce senza chiave");
            }

            book.Put(entry);
        }

        book._choices.AddRange(Required(file.Choices));
        book._review = [.. Required(file.Review)];
        book.ReviewAt = file.ReviewAt;
        foreach (var key in Required(file.Accepted))
        {
            book._accepted.Add(key);
        }

        return book;
    }

    public DownloadFile ToFile() => new()
    {
        Entries = [.. _entries.Values],
        Choices = Choices.ToList(),
        Review = [.. _review],
        ReviewAt = ReviewAt,
        Accepted = [.. _accepted],
    };

    private static List<T> Required<T>(List<T>? list) =>
        list is null || list.Contains(default!) ? throw new FormatException("elenco o voce null") : list;
}
