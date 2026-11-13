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

    /// <summary>Il client di download ha rifiutato la release (Sonarr/Radarr rispondono 5xx al grab); resta in "Serve te" e si riprova piano (spec T §7, §8.1).</summary>
    public const string GrabRefused = "GrabRefused";
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

    /// <summary><c>NothingFound</c>, <c>BelowMinScore</c>, <c>ImportBlocked</c>, <c>SearchFailed</c>, <c>GrabRefused</c> o null.</summary>
    public string? Reason { get; set; }

    public DateTimeOffset AvailableSince { get; set; }

    public DateTimeOffset? LastSearchAt { get; set; }

    public DateTimeOffset? NextSearchAt { get; set; }

    /// <summary>"Scarica subito": da quando la voce ha la precedenza nella coda del giro; null senza. Torna null a fine ricerca o quando la voce non si cerca più.</summary>
    public DateTimeOffset? RushAt { get; set; }

    public DateTimeOffset? UpgradeUntil { get; set; }

    public int? QueueId { get; set; }

    public long? LastSizeLeft { get; set; }

    public DateTimeOffset? LastProgressAt { get; set; }

    /// <summary>Da quando il torrent è fermo sul recupero dei metadati (il magnet non si risolve); null se non lo è.</summary>
    public DateTimeOffset? MetadataSince { get; set; }

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

    /// <summary>Quando l'admin ha premuto "Importa comunque": per un giro un import ancora bloccato in coda non torna in "Serve te".</summary>
    public DateTimeOffset? AdminImportAt { get; set; }

    /// <summary>Da quando l'elemento della coda è in "importPending" con un avviso (<c>IsImportRejected</c>); null se non lo è.</summary>
    public DateTimeOffset? ImportWarningSince { get; set; }

    public int ProfileId { get; set; }

    /// <summary>Il nome del profilo all'ultima scelta: serve all'obiettivo quando il file arriva.</summary>
    public string? ProfileName { get; set; }

    /// <summary>Durata di un episodio anche per una stagione: il pack la moltiplica (spec T §5.4).</summary>
    public int RuntimeMinutes { get; set; }

    /// <summary>Solo stagioni: i numeri degli episodi del pack scaricato, per cercarne gli upgrade.</summary>
    public List<int>? EpisodeNumbers { get; set; }

    /// <summary>Il tappabuchi proposto per questa voce: <see cref="DownloadStopgaps.Score"/>, <see cref="DownloadStopgaps.Size"/>, <see cref="DownloadStopgaps.Quality"/> o null.</summary>
    public string? Stopgap { get; set; }

    /// <summary>L'admin ha messo la voce in pausa: non si cerca più finché non cambia qualcosa.</summary>
    public bool Snoozed { get; set; }

    /// <summary>Il riassunto dell'ultima ricerca; null se non c'è ancora.</summary>
    public DownloadSummary? Summary { get; set; }

    /// <summary>Le release rifiutate dall'admin (<see cref="DownloadRule.ReleaseId"/>): la ricerca non le sceglie più.</summary>
    public List<string>? RefusedReleases { get; set; }

    /// <summary>L'id del download nel client, per ritrovarlo in coda.</summary>
    public string? DownloadId { get; set; }

    /// <summary>Il messaggio di Sonarr/Radarr per un import bloccato, così com'è.</summary>
    public string? BlockedMessage { get; set; }

    /// <summary>Il torrent messo da noi direttamente in qBittorrent (hash minuscolo): il giro lo importa per cartella quando finisce. Null senza.</summary>
    public string? DirectHash { get; set; }
}

/// <summary>Il tipo di tappabuchi di una voce (<c>DownloadEntry.Stopgap</c>).</summary>
public static class DownloadStopgaps
{
    /// <summary>Il migliore trovato, ma sotto il punteggio minimo.</summary>
    public const string Score = "Score";

    /// <summary>Il più pesante tra quelli troppo piccoli.</summary>
    public const string Size = "Size";

    /// <summary>Il miglior 720p scartato solo perché il profilo non lo ammette.</summary>
    public const string Quality = "Quality";
}

/// <summary>Il riassunto dell'ultima ricerca di una voce: serve a spiegare perché è in "Serve te".</summary>
public sealed class DownloadSummary
{
    /// <summary>Quante release ha trovato la ricerca.</summary>
    public int Found { get; set; }

    /// <summary>Il punteggio del miglior candidato che la regola accetta; null se non ce n'è.</summary>
    public int? BestScore { get; set; }

    public int MinScore { get; set; }

    /// <summary>Quante release erano sotto il peso minimo.</summary>
    public int TooSmall { get; set; }

    /// <summary>Quante release ha rifiutato Radarr/Sonarr.</summary>
    public int ArrRejected { get; set; }

    /// <summary>Il rifiuto di Radarr/Sonarr più frequente (testo com'è).</summary>
    public string? TopRejection { get; set; }

    /// <summary>C'è un tappabuchi da proporre (vedi <see cref="DownloadEntry.Stopgap"/>).</summary>
    public bool StopgapAvailable { get; set; }

    /// <summary>Il tipo del tappabuchi proposto (<see cref="DownloadStopgaps"/>), null se non c'è.</summary>
    public string? StopgapKind { get; set; }
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

    /// <summary>La qualità del file peggiore, per WouldImport di "Cerca un upgrade"; null negli elenchi salvati da versioni precedenti.</summary>
    public int? QualityId { get; set; }

    public int ProfileId { get; set; }

    /// <summary>Film monitorato, o serie e stagione monitorate: senza, il giro toglierebbe la voce prima di cercarla.</summary>
    public bool Monitored { get; set; }

    /// <summary>Durata del film o di un episodio, per il peso minimo della ricerca.</summary>
    public int RuntimeMinutes { get; set; }

    /// <summary>Solo stagioni: i numeri degli episodi dei file, per cercarne gli upgrade.</summary>
    public List<int>? EpisodeNumbers { get; set; }
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

    /// <summary>Le stagioni divise in episodi (<c>season:5:2</c>): non tornano più una voce sola (decisione 6).</summary>
    public List<string> SplitSeasons { get; set; } = [];

    /// <summary>I grab di "Alleggerisci" (spec U, piano 30d), per chiave, con il loro momento; manca nei file vecchi.</summary>
    public Dictionary<string, DateTimeOffset> Lightened { get; set; } = [];

    /// <summary>I torrent messi da noi in qBittorrent: hash minuscolo → chiave del titolo; manca nei file vecchi.</summary>
    public Dictionary<string, string> DirectGrabs { get; set; } = [];
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
    private readonly HashSet<string> _split = [];
    private readonly Dictionary<string, DateTimeOffset> _lightened = [];
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
        return RemoveFromReview(key) || added;
    }

    /// <summary>Toglie il titolo dall'elenco (per esempio dopo un download scelto dall'admin); true se c'era.</summary>
    public bool RemoveFromReview(string key) => _review.RemoveAll(r => r.Key == key) > 0;

    public bool IsAccepted(string key) => _accepted.Contains(key);

    /// <summary>La stagione si è divisa in episodi: da qui in poi resta divisa.</summary>
    public void Split(string seasonKey) => _split.Add(seasonKey);

    public bool IsSplit(string seasonKey) => _split.Contains(seasonKey);

    public IReadOnlyDictionary<string, DateTimeOffset> Lightened => _lightened;

    /// <summary>Un grab di "Alleggerisci": la scheda spazio ne segue il download.</summary>
    public void MarkLightened(string key, DateTimeOffset at) => _lightened[key] = at;

    /// <summary>True se la chiave c'era.</summary>
    public bool ForgetLightened(string key) => _lightened.Remove(key);

    /// <summary>I torrent messi da noi in qBittorrent: hash minuscolo → chiave del titolo. Una voce resta finché il torrent esiste.</summary>
    public Dictionary<string, string> DirectGrabs { get; private set; } = [];

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

        book._split.UnionWith(Required(file.SplitSeasons));

        // Un "Lightened": null scritto a mano vale come vuoto, come il campo che manca.
        foreach (var (key, at) in file.Lightened ?? [])
        {
            book._lightened[key] = at;
        }

        // Come "Lightened": il campo manca nei file vecchi.
        book.DirectGrabs = new(file.DirectGrabs ?? []);

        return book;
    }

    public DownloadFile ToFile() => new()
    {
        Entries = [.. _entries.Values],
        Choices = Choices.ToList(),
        Review = [.. _review],
        ReviewAt = ReviewAt,
        Accepted = [.. _accepted],
        SplitSeasons = [.. _split],
        Lightened = new(_lightened),
        DirectGrabs = new(DirectGrabs),
    };

    private static List<T> Required<T>(List<T>? list) =>
        list is null || list.Contains(default!) ? throw new FormatException("elenco o voce null") : list;
}
