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
    [property: JsonPropertyName("Seeders")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  int? Seeders);

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
    [property: JsonPropertyName("NextSearchAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? NextSearchAt);

/// <summary>Un titolo da ripassare con il file di adesso (spec T §6).</summary>
public sealed record ReviewItemDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? PosterUrl,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Quality")] string Quality);

/// <summary>Risposta di GET Downloads (spec T §8.1). Recent dalla più recente; gli errori sono quelli dell'ultimo giro.</summary>
public sealed record DownloadsOverviewDto(
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Recent")] IReadOnlyList<DownloadChoiceDto> Recent,
    [property: JsonPropertyName("Waiting")] IReadOnlyList<DownloadItemDto> Waiting,
    [property: JsonPropertyName("Review")] IReadOnlyList<ReviewItemDto> Review,
    [property: JsonPropertyName("ReviewAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DateTimeOffset? ReviewAt,
    [property: JsonPropertyName("SonarrError")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? SonarrError,
    [property: JsonPropertyName("RadarrError")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  string? RadarrError);

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
/// Release null: nessun singolo valido. WouldImport: Radarr/Sonarr lo importerebbero al posto del file di quell'episodio.
/// </summary>
public sealed record DownloadEpisodeChoiceDto(
    [property: JsonPropertyName("EpisodeNumber")] int EpisodeNumber,
    [property: JsonPropertyName("Release")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]  DownloadReleaseDto? Release,
    [property: JsonPropertyName("WouldImport")] bool WouldImport);

/// <summary>
/// Risposta di GET Downloads/Search (spec T §8.2). Con Error (un codice di UpcomingErrors) le liste sono vuote.
/// EpisodeChoices (dalla 1.15.0): i migliori singoli per episodio, solo per una stagione senza un pack scelto; altrimenti vuota.
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
    [property: JsonPropertyName("EpisodeChoices")] IReadOnlyList<DownloadEpisodeChoiceDto> EpisodeChoices);

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
}

/// <summary>Corpo di POST Downloads/Accept e Downloads/SearchNow (spec T §7.4).</summary>
public sealed class KeyRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }
}

/// <summary>Errore dei download: "Expired" (409) o "Unavailable" (503) (spec T §7.4).</summary>
public sealed record DownloadsErrorDto([property: JsonPropertyName("Reason")] string Reason);
