using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Stato di un titolo o di una stagione per l'app (spec I §7.3).</summary>
public static class TitleStatuses
{
    public const string None = "None";
    public const string Pending = "Pending";
    public const string Processing = "Processing";
    public const string Partial = "Partial";
    public const string Available = "Available";
}

/// <summary>Stato di una richiesta per l'app (spec I §7.3).</summary>
public static class RequestStatuses
{
    public const string Pending = "Pending";
    public const string Approved = "Approved";
    public const string Downloading = "Downloading";
    public const string Partial = "Partial";
    public const string Available = "Available";
    public const string Declined = "Declined";
    public const string Failed = "Failed";
}

/// <summary>I due tipi di titolo, con i nomi di Seerr.</summary>
public static class RequestMediaTypes
{
    public const string Movie = "movie";
    public const string Tv = "tv";
}

/// <summary>Risposta di GET Requests/Me.</summary>
public sealed record RequestsMeResponse(
    [property: JsonPropertyName("CanRequest")] bool CanRequest,
    [property: JsonPropertyName("CanManage")] bool CanManage,
    [property: JsonPropertyName("HasAccount")] bool HasAccount);

/// <summary>Un risultato di GET Requests/Search.</summary>
public sealed record RequestableTitleDto(
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId);

/// <summary>Una stagione di una serie, senza gli speciali.</summary>
public sealed record SeasonDto(
    [property: JsonPropertyName("SeasonNumber")] int SeasonNumber,
    [property: JsonPropertyName("EpisodeCount")] int EpisodeCount,
    [property: JsonPropertyName("Status")] string Status);

/// <summary>Risposta di GET Requests/Movie/{id} e Requests/Tv/{id}; Seasons solo per le serie.</summary>
public sealed record TitleDetailsDto(
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("Overview")] string? Overview,
    [property: JsonPropertyName("Genres")] IReadOnlyList<string> Genres,
    [property: JsonPropertyName("RuntimeMinutes")] int? RuntimeMinutes,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("BackdropPath")] string? BackdropPath,
    [property: JsonPropertyName("TrailerUrl")] string? TrailerUrl,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId,
    [property: JsonPropertyName("RequestedByMe")] bool RequestedByMe,
    [property: JsonPropertyName("Requested")] bool Requested,
    [property: JsonPropertyName("Seasons"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    IReadOnlyList<SeasonDto>? Seasons);

/// <summary>Corpo di POST Requests.</summary>
public sealed class CreateRequestBody
{
    [JsonPropertyName("MediaType")]
    public string? MediaType { get; set; }

    [JsonPropertyName("TmdbId")]
    public int TmdbId { get; set; }

    /// <summary>Solo per le serie: le stagioni scelte.</summary>
    [JsonPropertyName("Seasons")]
    public List<int>? Seasons { get; set; }
}

/// <summary>Risposta di POST Requests: Status è "Pending" o, se Seerr l'ha approvata da sola, un altro stato.</summary>
public sealed record CreatedRequestDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Status")] string Status);

/// <summary>Chi ha chiesto il titolo.</summary>
public sealed record RequesterDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsMe")] bool IsMe);

/// <summary>Una richiesta negli elenchi (spec I §7.3); Title vuoto se Seerr non l'ha dato.</summary>
public sealed record MediaRequestDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("Seasons")] IReadOnlyList<int> Seasons,
    [property: JsonPropertyName("RequestedBy")] RequesterDto RequestedBy,
    [property: JsonPropertyName("CreatedAt")] DateTimeOffset CreatedAt,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("Progress")] double? Progress,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId);

/// <summary>Risposta di GET Requests.</summary>
public sealed record RequestPageDto(
    [property: JsonPropertyName("Items")] IReadOnlyList<MediaRequestDto> Items,
    [property: JsonPropertyName("HasMore")] bool HasMore);

public sealed record ProfileDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Name")] string Name);

/// <summary>Un server di Radarr o Sonarr per la finestra Approva.</summary>
public sealed record ServiceDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsDefault")] bool IsDefault,
    [property: JsonPropertyName("Profiles")] IReadOnlyList<ProfileDto> Profiles,
    [property: JsonPropertyName("RootFolders")] IReadOnlyList<string> RootFolders,
    [property: JsonPropertyName("DefaultProfileId")] int? DefaultProfileId,
    [property: JsonPropertyName("DefaultRootFolder")] string? DefaultRootFolder);

/// <summary>Corpo di POST Requests/{id}/Approve: tutto vuoto = valori predefiniti di Seerr.</summary>
public sealed class ApproveBody
{
    [JsonPropertyName("ServerId")]
    public int? ServerId { get; set; }

    [JsonPropertyName("ProfileId")]
    public int? ProfileId { get; set; }

    [JsonPropertyName("RootFolder")]
    public string? RootFolder { get; set; }
}

/// <summary>Corpo degli errori degli endpoint delle richieste (spec I §7.3).</summary>
public sealed record RequestsErrorDto(
    [property: JsonPropertyName("Code")] string Code);

/// <summary>Risposta di POST Requests/Test (pagina del plugin).</summary>
public sealed record SeerrTestResponse(
    [property: JsonPropertyName("Ok")] bool Ok,
    [property: JsonPropertyName("Version")] string? Version,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Risposta di GET Requests/Admin (pagina del plugin).</summary>
public sealed record RequestsAdminStatus(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("LastEventAt")] DateTimeOffset? LastEventAt,
    [property: JsonPropertyName("LastEventType")] string? LastEventType);
