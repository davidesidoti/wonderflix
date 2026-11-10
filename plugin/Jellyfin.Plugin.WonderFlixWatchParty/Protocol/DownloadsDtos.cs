using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Una release, trovata o scelta (spec T §7.4). Quality è il nome ("WEBRip-1080p"), Resolution l'altezza.</summary>
public sealed record DownloadReleaseDto(
    [property: JsonPropertyName("Guid")] string Guid,
    [property: JsonPropertyName("IndexerId")] int IndexerId,
    [property: JsonPropertyName("Indexer")] string Indexer,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Quality")] string Quality,
    [property: JsonPropertyName("Resolution")] int Resolution,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Seeders")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  int? Seeders,
    [property: JsonPropertyName("FullSeason")] bool FullSeason = false);

/// <summary>Una scelta fatta, da WonderFlix o dall'admin (spec T §8.1). Previous*: il file di prima, per un upgrade.</summary>
public sealed record DownloadChoiceDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? PosterUrl,
    [property: JsonPropertyName("At")] DateTimeOffset At,
    [property: JsonPropertyName("Release")] DownloadReleaseDto Release,
    [property: JsonPropertyName("PreviousSizeBytes")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  long? PreviousSizeBytes,
    [property: JsonPropertyName("PreviousScore")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  int? PreviousScore,
    [property: JsonPropertyName("ByAdmin")] bool ByAdmin);

/// <summary>Un titolo seguito (spec T §8.1): in attesa, in download, in upgrade o "Serve te".</summary>
public sealed record DownloadItemDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? PosterUrl,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Reason")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? Reason,
    [property: JsonPropertyName("AvailableSince")] DateTimeOffset AvailableSince,
    [property: JsonPropertyName("LastSearchAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? LastSearchAt,
    [property: JsonPropertyName("NextSearchAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? NextSearchAt,
    [property: JsonPropertyName("Actions")] IReadOnlyList<string> Actions,
    [property: JsonPropertyName("Summary")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DownloadSummaryDto? Summary,
    [property: JsonPropertyName("BlockedMessage")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? BlockedMessage,
    [property: JsonPropertyName("Snoozed")] bool Snoozed,
    [property: JsonPropertyName("Progress")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DownloadProgressDto? Progress,
    [property: JsonPropertyName("SearchPhase")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? SearchPhase = null,
    [property: JsonPropertyName("ExternalSearchUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? ExternalSearchUrl = null,
    [property: JsonPropertyName("SeriesId")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? SeriesId = null,
    [property: JsonPropertyName("CanRush")] bool CanRush = false,
    [property: JsonPropertyName("Rush")] bool Rush = false);

/// <summary>L'avanzamento di un download dalla coda di Radarr/Sonarr; Status è il codice della coda, in minuscolo come arriva ("downloading", "queued", "paused", ...), o "metadata" se il torrent è fermo sul recupero dei metadati: allora Since è da quando.</summary>
public sealed record DownloadProgressDto(
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("SizeLeftBytes")] long SizeLeftBytes,
    [property: JsonPropertyName("EstimatedCompletion")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? EstimatedCompletion,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("Since")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? Since = null);

/// <summary>Il riassunto dell'ultima ricerca di una voce in "Serve te": numeri, nessun testo tranne il rifiuto di Sonarr/Radarr.</summary>
public sealed record DownloadSummaryDto(
    [property: JsonPropertyName("Found")] int Found,
    [property: JsonPropertyName("BestScore")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  int? BestScore,
    [property: JsonPropertyName("MinScore")] int MinScore,
    [property: JsonPropertyName("TooSmall")] int TooSmall,
    [property: JsonPropertyName("ArrRejected")] int ArrRejected,
    [property: JsonPropertyName("TopRejection")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? TopRejection,
    [property: JsonPropertyName("StopgapAvailable")] bool StopgapAvailable);

/// <summary>Un titolo da ripassare con il file di adesso (spec T §6).</summary>
public sealed record ReviewItemDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? PosterUrl,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Quality")] string Quality,
    [property: JsonPropertyName("CanHunt")] bool CanHunt);

/// <summary>Risposta di GET Downloads (spec T §8.1). Recent dalla più recente; gli errori sono quelli dell'ultimo giro.</summary>
public sealed record DownloadsOverviewDto(
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Recent")] IReadOnlyList<DownloadChoiceDto> Recent,
    [property: JsonPropertyName("Waiting")] IReadOnlyList<DownloadItemDto> Waiting,
    [property: JsonPropertyName("Review")] IReadOnlyList<ReviewItemDto> Review,
    [property: JsonPropertyName("ReviewAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? ReviewAt,
    [property: JsonPropertyName("SonarrError")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? SonarrError,
    [property: JsonPropertyName("RadarrError")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? RadarrError,
    [property: JsonPropertyName("Unknown")] IReadOnlyList<UnknownDownloadDto> Unknown,
    [property: JsonPropertyName("Progress")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] SearchProgressDto? Progress = null,
    [property: JsonPropertyName("RefreshPending")] bool RefreshPending = false);

/// <summary>
/// L'avanzamento della coda dei download automatici (dalla 1.25.0): Done le ricerche del giro da quando la coda non è
/// più vuota (solo in memoria, da 0 dopo un riavvio), Remaining le voci da cercare, PerHour le ricerche all'ora delle
/// ultime 2 ore (null con meno di 3), EstimatedEnd la fine stimata (null in pausa, senza ritmo o con una ricerca manuale), Paused il giro spento.
/// Dalla 1.26.0 ManualSearch: una ricerca dell'admin aspetta o è in corso, e il giro non ne avvia di nuove.
/// </summary>
public sealed record SearchProgressDto(
    [property: JsonPropertyName("Done")] int Done,
    [property: JsonPropertyName("Remaining")] int Remaining,
    [property: JsonPropertyName("PerHour")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? PerHour,
    [property: JsonPropertyName("EstimatedEnd")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? EstimatedEnd,
    [property: JsonPropertyName("Paused")] bool Paused,
    [property: JsonPropertyName("ManualSearch")] bool ManualSearch = false);

/// <summary>Un download fermo all'import senza serie né film: Service "Sonarr" o "Radarr".</summary>
public sealed record UnknownDownloadDto(
    [property: JsonPropertyName("Service")] string Service,
    [property: JsonPropertyName("DownloadId")] string DownloadId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Message")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? Message);

/// <summary>Una release valida, nell'ordine della regola (Rank da 1) (spec T §8.2).</summary>
public sealed record DownloadCandidateDto(
    [property: JsonPropertyName("Rank")] int Rank,
    [property: JsonPropertyName("Release")] DownloadReleaseDto Release,
    [property: JsonPropertyName("IsChoice")] bool IsChoice,
    [property: JsonPropertyName("WouldImport")] bool WouldImport);

/// <summary>Una release scartata: Reason "Arr" (Detail = il rifiuto) o "TooSmall" (Detail = GB all'ora) (spec T §8.2).</summary>
public sealed record DownloadRejectedDto(
    [property: JsonPropertyName("Release")] DownloadReleaseDto Release,
    [property: JsonPropertyName("Reason")] string Reason,
    [property: JsonPropertyName("Detail")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? Detail);

/// <summary>Il file di adesso; per una stagione il peso di tutti i file e il punteggio e la qualità del peggiore (spec T §8.2).</summary>
public sealed record DownloadCurrentFileDto(
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Quality")] string Quality);

/// <summary>
/// Il singolo migliore di un episodio nella ricerca di una stagione senza un pack conveniente (spec T §5.4, §8.2).
/// Release null: nessun singolo valido. WouldImport: Sonarr lo importerebbe al posto del file di quell'episodio.
/// CurrentScore: il punteggio del file di quell'episodio (il peggiore se più d'uno), null senza file.
/// </summary>
public sealed record DownloadEpisodeChoiceDto(
    [property: JsonPropertyName("EpisodeNumber")] int EpisodeNumber,
    [property: JsonPropertyName("Release")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DownloadReleaseDto? Release,
    [property: JsonPropertyName("WouldImport")] bool WouldImport,
    [property: JsonPropertyName("CurrentScore")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? CurrentScore);

/// <summary>
/// Risposta di GET Downloads/Search (spec T §8.2). Con Error (un codice di UpcomingErrors) le liste sono vuote.
/// EpisodeChoices (dalla 1.15.0): i migliori singoli per episodio, solo per una stagione senza un pack scelto; altrimenti vuota.
/// ExternalSearchUrl: la ricerca sul tracker esterno per questo titolo, null senza link nelle impostazioni.
/// </summary>
public sealed record DownloadSearchDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("RuntimeMinutes")] int RuntimeMinutes,
    [property: JsonPropertyName("Current")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DownloadCurrentFileDto? Current,
    [property: JsonPropertyName("Candidates")] IReadOnlyList<DownloadCandidateDto> Candidates,
    [property: JsonPropertyName("Rejected")] IReadOnlyList<DownloadRejectedDto> Rejected,
    [property: JsonPropertyName("ValidCount")] int ValidCount,
    [property: JsonPropertyName("TotalCount")] int TotalCount,
    [property: JsonPropertyName("Error")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? Error,
    [property: JsonPropertyName("EpisodeChoices")] IReadOnlyList<DownloadEpisodeChoiceDto> EpisodeChoices,
    [property: JsonPropertyName("ExternalSearchUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? ExternalSearchUrl);

/// <summary>
/// Risposta di POST Downloads/SearchStart e GET Downloads/SearchStatus (spec W §4.4). State: uno di DownloadSearchStates.
/// StartedAt: l'inizio del job, con Done l'ora della ricerca. Service: "Radarr" o "Sonarr". Result solo con Done.
/// Dalla 1.26.0 WaitingFor: con Running, la ricerca automatica che il job aspetta (StartedAt è allora l'inizio del job,
/// poi quello vero della ricerca); null negli altri casi.
/// </summary>
public sealed record DownloadSearchStatusDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("StartedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? StartedAt,
    [property: JsonPropertyName("Service")] string Service,
    [property: JsonPropertyName("Result")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DownloadSearchDto? Result,
    [property: JsonPropertyName("WaitingFor")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] SearchWaitDto? WaitingFor = null);

/// <summary>
/// La ricerca automatica che una ricerca dell'admin aspetta (dalla 1.26.0): Title la voce, Since quando è partita,
/// TypicalSeconds la media delle ultime 10 ricerche automatiche (null con meno di 3).
/// </summary>
public sealed record SearchWaitDto(
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Since")] DateTimeOffset Since,
    [property: JsonPropertyName("TypicalSeconds")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? TypicalSeconds);

/// <summary>Un profilo di qualità con le sue soglie (spec T §7.1). Service: "Radarr" o "Sonarr".</summary>
public sealed record DownloadProfileDto(
    [property: JsonPropertyName("Service")] string Service,
    [property: JsonPropertyName("ProfileId")] int ProfileId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("MinScore")] int MinScore,
    [property: JsonPropertyName("TargetScore")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  int? TargetScore);

/// <summary>Corpo di POST Downloads/Grab: la release di una ricerca (spec T §7.4).</summary>
public sealed class GrabRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }

    [JsonPropertyName("Guid")]
    public string? Guid { get; set; }

    [JsonPropertyName("IndexerId")]
    public int IndexerId { get; set; }

    /// <summary>"Alleggerisci" (spec U): a download scelto il titolo diventa "va bene così" e non si cercano upgrade.</summary>
    [JsonPropertyName("Lighten")]
    public bool Lighten { get; set; }
}

/// <summary>Corpo di POST Downloads/Accept e Downloads/SearchNow (spec T §7.4).</summary>
public sealed class KeyRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }
}

/// <summary>Corpo di POST Downloads/ImportExisting: il titolo e il torrent già in qBittorrent da cui importare.</summary>
public sealed class ImportExistingRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }

    [JsonPropertyName("Hash")]
    public string? Hash { get; set; }

    /// <summary>Come in <see cref="GrabRequest.Lighten"/>: l'import parte da "Alleggerisci".</summary>
    [JsonPropertyName("Lighten")]
    public bool Lighten { get; set; }
}

/// <summary>Corpo di POST Downloads/RemoveUnknown.</summary>
public sealed class RemoveUnknownRequest
{
    [JsonPropertyName("Service")]
    public string? Service { get; set; }

    [JsonPropertyName("DownloadId")]
    public string? DownloadId { get; set; }
}

/// <summary>Corpo di POST Downloads/SearchStart (spec W §4.4): Again = true cerca di nuovo anche se c'è un risultato recente.</summary>
public sealed class SearchStartRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }

    [JsonPropertyName("Again")]
    public bool Again { get; set; }
}

/// <summary>Errore dei download: "Expired" (409) o "Unavailable" (503) (spec T §7.4).</summary>
public sealed record DownloadsErrorDto([property: JsonPropertyName("Reason")] string Reason);

/// <summary>
/// 502 di Downloads/Grab quando il torrent è già in qBittorrent: Reason resta "Refused" (le app vecchie vedono l'errore di
/// sempre), Hash e Name dicono quale torrent offrire per Downloads/ImportExisting.
/// </summary>
public sealed record DownloadsRefusedDto(
    [property: JsonPropertyName("Reason")] string Reason,
    [property: JsonPropertyName("Hash")] string Hash,
    [property: JsonPropertyName("Name")] string Name);
