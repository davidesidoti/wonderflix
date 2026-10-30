using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un passo di un'operazione dello spazio, con lo stato e il motivo (spec U §6.1).</summary>
public sealed record SpaceStepDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Detail")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Detail,
    [property: JsonPropertyName("Done")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? Done,
    [property: JsonPropertyName("Waiting")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? Waiting);

/// <summary>Un'operazione dello spazio: i passi, lo stato e i byte attesi e liberati (spec U §6.1 e §6.2).</summary>
public sealed record SpaceOperationDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Auto")] bool Auto,
    [property: JsonPropertyName("StartedAt")] DateTimeOffset StartedAt,
    [property: JsonPropertyName("EndedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? EndedAt,
    [property: JsonPropertyName("EstimatedFreedBytes")] long EstimatedFreedBytes,
    [property: JsonPropertyName("PendingBytes")] long PendingBytes,
    [property: JsonPropertyName("QuotaBeforeBytes")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] long? QuotaBeforeBytes,
    [property: JsonPropertyName("QuotaAfterBytes")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] long? QuotaAfterBytes,
    [property: JsonPropertyName("Steps")] IReadOnlyList<SpaceStepDto> Steps);

/// <summary>La quota del seedbox in byte (spec U §5.4).</summary>
public sealed record SpaceQuotaDto(
    [property: JsonPropertyName("UsedBytes")] long UsedBytes,
    [property: JsonPropertyName("LimitBytes")] long LimitBytes);

/// <summary>Come si divide lo spazio usato (spec U §5.4). <c>OtherBytes</c> è il resto della quota, 0 senza quota.</summary>
public sealed record SpaceBreakdownDto(
    [property: JsonPropertyName("MoviesBytes")] long MoviesBytes,
    [property: JsonPropertyName("SeriesBytes")] long SeriesBytes,
    [property: JsonPropertyName("AnimeBytes")] long AnimeBytes,
    [property: JsonPropertyName("TorrentOnlyBytes")] long TorrentOnlyBytes,
    [property: JsonPropertyName("OtherBytes")] long OtherBytes);

/// <summary>Chi ha aperto un titolo, se l'ha finito e quando l'ha guardato l'ultima volta (spec U §4.1).</summary>
public sealed record SpaceViewerDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Finished")] bool Finished,
    [property: JsonPropertyName("LastPlayed")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? LastPlayed);

/// <summary>Una richiesta Seerr del titolo (spec U §4.2).</summary>
public sealed record SpaceRequestDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("At")] DateTimeOffset At);

/// <summary>Una riga di Cancellare: film, serie o stagione, con i segnali e i GB liberabili (spec U §5.1).</summary>
public sealed record SpaceCandidateDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? Year,
    [property: JsonPropertyName("SeasonNumber")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? SeasonNumber,
    [property: JsonPropertyName("SeriesKey")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? SeriesKey,
    [property: JsonPropertyName("ItemId")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? ItemId,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? PosterUrl,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("FreeNowBytes")] long FreeNowBytes,
    [property: JsonPropertyName("FreeLaterBytes")] long FreeLaterBytes,
    [property: JsonPropertyName("FreeLaterAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? FreeLaterAt,
    [property: JsonPropertyName("InPackBytes")] long InPackBytes,
    [property: JsonPropertyName("Via")] IReadOnlyList<string> Via,
    [property: JsonPropertyName("Keep")] IReadOnlyList<string> Keep,
    [property: JsonPropertyName("Viewers")] IReadOnlyList<SpaceViewerDto> Viewers,
    [property: JsonPropertyName("Requests")] IReadOnlyList<SpaceRequestDto> Requests,
    [property: JsonPropertyName("RatingAvg")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? RatingAvg,
    [property: JsonPropertyName("RatingCount")] int RatingCount,
    [property: JsonPropertyName("LastOpened")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? LastOpened,
    [property: JsonPropertyName("Added")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? Added,
    [property: JsonPropertyName("Genres")] IReadOnlyList<string> Genres);

/// <summary>Una riga di Alleggerire: un film o una stagione oltre la soglia di GB all'ora (spec U §5.2).</summary>
public sealed record SpaceLightenDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("SeasonNumber")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? SeasonNumber,
    [property: JsonPropertyName("ItemId")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? ItemId,
    [property: JsonPropertyName("PosterUrl")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? PosterUrl,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("ExcessBytes")] long ExcessBytes,
    [property: JsonPropertyName("GbPerHour")] double GbPerHour);

/// <summary>Un torrent senza copia in libreria (spec U §5.3); <c>Tracker</c> è l'host.</summary>
public sealed record SpaceTorrentDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Hash")] string Hash,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Tracker")] string Tracker,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Ratio")] double Ratio,
    [property: JsonPropertyName("SeedingDays")] double SeedingDays,
    [property: JsonPropertyName("CanRemoveNow")] bool CanRemoveNow,
    [property: JsonPropertyName("ExpectedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? ExpectedAt);

/// <summary>Un file orfano o doppione (spec U §5.3). <c>Linked</c>: ha altri hardlink, cancellarlo non libera spazio.</summary>
public sealed record SpaceFileDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Path")] string Path,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("Linked")] bool Linked);

/// <summary>La Pulizia: torrent senza copia in libreria, file orfani e doppioni (spec U §5.3).</summary>
public sealed record SpaceCleanupDto(
    [property: JsonPropertyName("Torrents")] IReadOnlyList<SpaceTorrentDto> Torrents,
    [property: JsonPropertyName("Orphans")] IReadOnlyList<SpaceFileDto> Orphans,
    [property: JsonPropertyName("Duplicates")] IReadOnlyList<SpaceFileDto> Duplicates);

/// <summary>Un torrent in attesa di fine seed obbligatorio (spec U §6.3).</summary>
public sealed record SpacePendingDto(
    [property: JsonPropertyName("Hash")] string Hash,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Tracker")] string Tracker,
    [property: JsonPropertyName("SizeBytes")] long SizeBytes,
    [property: JsonPropertyName("ExpectedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? ExpectedAt,
    [property: JsonPropertyName("Title")] string Title);

/// <summary>Un titolo tenuto con "Tienilo" (spec U §6.4).</summary>
public sealed record SpaceKeptDto(
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Title")] string Title);

/// <summary>I servizi che il calcolo non ha potuto leggere: <c>NotConfigured</c>, <c>Unauthorized</c> o <c>Unreachable</c> (spec U §6.5).</summary>
public sealed record SpaceErrorsDto(
    [property: JsonPropertyName("Radarr")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Radarr,
    [property: JsonPropertyName("Sonarr")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Sonarr,
    [property: JsonPropertyName("Qbit")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Qbit,
    [property: JsonPropertyName("Seerr")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Seerr,
    [property: JsonPropertyName("Quota")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Quota);

/// <summary><c>GET Space</c> (spec U §7.4): l'ultimo calcolo per chi chiama, con attese, tenuti e ultime operazioni.</summary>
public sealed record SpaceOverviewDto(
    [property: JsonPropertyName("ScannedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? ScannedAt,
    [property: JsonPropertyName("Scanning")] bool Scanning,
    [property: JsonPropertyName("Quota")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] SpaceQuotaDto? Quota,
    [property: JsonPropertyName("Breakdown")] SpaceBreakdownDto Breakdown,
    [property: JsonPropertyName("Delete")] IReadOnlyList<SpaceCandidateDto> Delete,
    [property: JsonPropertyName("Lighten")] IReadOnlyList<SpaceLightenDto> Lighten,
    [property: JsonPropertyName("Cleanup")] SpaceCleanupDto Cleanup,
    [property: JsonPropertyName("Pending")] IReadOnlyList<SpacePendingDto> Pending,
    [property: JsonPropertyName("Kept")] IReadOnlyList<SpaceKeptDto> Kept,
    [property: JsonPropertyName("Operations")] IReadOnlyList<SpaceOperationDto> Operations,
    [property: JsonPropertyName("TopGenres")] IReadOnlyList<string> TopGenres,
    [property: JsonPropertyName("Errors")] SpaceErrorsDto Errors);

/// <summary>Risposta di <c>POST Space/Operations</c>: l'id con cui seguire l'operazione (spec U §7.4).</summary>
public sealed record SpaceStartedDto([property: JsonPropertyName("Id")] string Id);

/// <summary>Errore dello spazio: <c>Unknown</c>, <c>Busy</c> o <c>NotReady</c> (spec U §7.4).</summary>
public sealed record SpaceErrorDto([property: JsonPropertyName("Reason")] string Reason);

/// <summary>Corpo di <c>POST Space/Operations</c> (spec U §7.4).</summary>
public sealed class StartOperationRequest
{
    [JsonPropertyName("Kind")]
    public string? Kind { get; set; }

    [JsonPropertyName("Key")]
    public string? Key { get; set; }
}

/// <summary>Corpo di <c>POST Space/Kept</c> (spec U §7.4).</summary>
public sealed class KeepRequest
{
    [JsonPropertyName("Key")]
    public string? Key { get; set; }

    [JsonPropertyName("Title")]
    public string? Title { get; set; }
}
