using System.Text.Json;
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

// Le forme JSON di Seerr 3.x usate dal plugin (spec I §3), solo con i campi
// che servono. Si leggono e si scrivono con SeerrJson.Options: camelCase,
// maiuscole ignorate in lettura.

internal static class SeerrJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}

public sealed class SeerrStatusInfo
{
    public string? Version { get; set; }
}

public sealed class SeerrUser
{
    public int Id { get; set; }

    public int Permissions { get; set; }

    /// <summary>Id dell'utente Jellyfin, in formato "N" (può puntare a un utente cancellato).</summary>
    public string? JellyfinUserId { get; set; }

    public string? DisplayName { get; set; }
}

public sealed class SeerrPageInfo
{
    /// <summary>Quanti elementi in tutto.</summary>
    public int Results { get; set; }
}

public sealed class SeerrPage<T>
{
    public SeerrPageInfo? PageInfo { get; set; }

    public List<T> Results { get; set; } = [];
}

public sealed class SeerrMainSettings
{
    public int DefaultPermissions { get; set; }
}

public sealed class SeerrSearchPage
{
    public List<SeerrSearchResult> Results { get; set; } = [];
}

public sealed class SeerrSearchResult
{
    /// <summary>Id TMDB.</summary>
    public int Id { get; set; }

    /// <summary>"movie", "tv" o "person".</summary>
    public string? MediaType { get; set; }

    /// <summary>Film.</summary>
    public string? Title { get; set; }

    /// <summary>Serie e persone.</summary>
    public string? Name { get; set; }

    public string? ReleaseDate { get; set; }

    public string? FirstAirDate { get; set; }

    public string? PosterPath { get; set; }

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrMediaInfo
{
    public int Status { get; set; }

    public string? JellyfinMediaId { get; set; }

    public List<SeerrMediaSeason> Seasons { get; set; } = [];

    public List<SeerrRequest> Requests { get; set; } = [];

    public List<SeerrDownload> DownloadStatus { get; set; } = [];
}

public sealed class SeerrMediaSeason
{
    public int SeasonNumber { get; set; }

    public int Status { get; set; }
}

public sealed class SeerrDownload
{
    public double Size { get; set; }

    public double SizeLeft { get; set; }
}

public sealed class SeerrGenre
{
    public string? Name { get; set; }
}

public sealed class SeerrVideo
{
    /// <summary>"Trailer", "Teaser", "Clip"…</summary>
    public string? Type { get; set; }

    public string? Site { get; set; }

    public string? Url { get; set; }
}

public sealed class SeerrMovie
{
    public int Id { get; set; }

    public string? Title { get; set; }

    public string? ReleaseDate { get; set; }

    public string? Overview { get; set; }

    /// <summary>Durata in minuti.</summary>
    public int? Runtime { get; set; }

    public List<SeerrGenre> Genres { get; set; } = [];

    public string? PosterPath { get; set; }

    public string? BackdropPath { get; set; }

    public List<SeerrVideo> RelatedVideos { get; set; } = [];

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrTvSeason
{
    public int SeasonNumber { get; set; }

    public int EpisodeCount { get; set; }
}

public sealed class SeerrTv
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public string? FirstAirDate { get; set; }

    public string? Overview { get; set; }

    public List<SeerrGenre> Genres { get; set; } = [];

    public string? PosterPath { get; set; }

    public string? BackdropPath { get; set; }

    public List<SeerrVideo> RelatedVideos { get; set; } = [];

    /// <summary>Anche la stagione 0 (speciali), se TMDB ce l'ha.</summary>
    public List<SeerrTvSeason> Seasons { get; set; } = [];

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrRequestUser
{
    public int Id { get; set; }

    public string? DisplayName { get; set; }

    public string? JellyfinUserId { get; set; }
}

public sealed class SeerrRequestSeason
{
    public int SeasonNumber { get; set; }
}

public sealed class SeerrRequestMedia
{
    public int TmdbId { get; set; }

    public string? MediaType { get; set; }

    public int Status { get; set; }

    public string? JellyfinMediaId { get; set; }

    public List<SeerrDownload> DownloadStatus { get; set; } = [];
}

public sealed class SeerrRequest
{
    public int Id { get; set; }

    public int Status { get; set; }

    /// <summary>"movie" o "tv".</summary>
    public string? Type { get; set; }

    public bool Is4k { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public List<SeerrRequestSeason> Seasons { get; set; } = [];

    public SeerrRequestUser? RequestedBy { get; set; }

    public SeerrRequestMedia? Media { get; set; }
}

public sealed class SeerrServer
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public bool Is4k { get; set; }

    public bool IsDefault { get; set; }

    public int? ActiveProfileId { get; set; }

    public string? ActiveDirectory { get; set; }
}

public sealed class SeerrProfile
{
    public int Id { get; set; }

    public string? Name { get; set; }
}

public sealed class SeerrRootFolder
{
    public string? Path { get; set; }
}

public sealed class SeerrServerDetails
{
    public List<SeerrProfile> Profiles { get; set; } = [];

    public List<SeerrRootFolder> RootFolders { get; set; } = [];
}

/// <summary>Corpo di POST /request.</summary>
public sealed class SeerrCreateRequest
{
    public string MediaType { get; set; } = string.Empty;

    /// <summary>Id TMDB.</summary>
    public int MediaId { get; set; }

    /// <summary>Solo per le serie.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }
}

/// <summary>Corpo di PUT /request/{id}: server, profilo e cartella scelti all'approvazione.</summary>
public sealed class SeerrUpdateRequest
{
    public string MediaType { get; set; } = string.Empty;

    public int ServerId { get; set; }

    public int ProfileId { get; set; }

    public string RootFolder { get; set; } = string.Empty;

    /// <summary>Obbligatorie per le serie: quelle della richiesta.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }
}

/// <summary>Corpo di POST /user/import-from-jellyfin.</summary>
public sealed class SeerrImportUsers
{
    public List<string> JellyfinUserIds { get; set; } = [];
}

/// <summary>
/// Il corpo del webhook, dal modello della pagina del plugin (spec I §7.1):
/// testi già sostituiti da Seerr; "extra" viene dalla chiave speciale
/// "{{extra}}".
/// </summary>
public sealed class SeerrWebhookPayload
{
    public string? Secret { get; set; }

    [JsonPropertyName("notification_type")]
    public string? NotificationType { get; set; }

    public string? Subject { get; set; }

    [JsonPropertyName("request_id")]
    public string? RequestId { get; set; }

    [JsonPropertyName("media_type")]
    public string? MediaType { get; set; }

    [JsonPropertyName("media_tmdbid")]
    public string? MediaTmdbId { get; set; }

    [JsonPropertyName("media_jellyfinMediaId")]
    public string? MediaJellyfinMediaId { get; set; }

    [JsonPropertyName("requestedBy_jellyfinUserId")]
    public string? RequestedByJellyfinUserId { get; set; }

    [JsonPropertyName("requestedBy_username")]
    public string? RequestedByUsername { get; set; }

    public List<SeerrWebhookExtra>? Extra { get; set; }
}

public sealed class SeerrWebhookExtra
{
    public string? Name { get; set; }

    public string? Value { get; set; }
}
