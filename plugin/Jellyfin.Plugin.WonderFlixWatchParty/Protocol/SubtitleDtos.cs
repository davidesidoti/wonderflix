using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un sottotitolo trovato dai provider, appiattito per l'app (spec R §6.4).</summary>
public sealed record RemoteSubtitleDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("ProviderName")] string ProviderName,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Language")] string Language,
    [property: JsonPropertyName("Format")] string Format,
    [property: JsonPropertyName("CommunityRating"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] float? CommunityRating,
    [property: JsonPropertyName("DownloadCount"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? DownloadCount,
    [property: JsonPropertyName("IsHashMatch")] bool IsHashMatch,
    [property: JsonPropertyName("HearingImpaired")] bool HearingImpaired,
    [property: JsonPropertyName("Forced")] bool Forced,
    [property: JsonPropertyName("MachineTranslated")] bool MachineTranslated);

/// <summary>I motivi degli errori 502 degli endpoint dei sottotitoli, nel corpo {Reason}.</summary>
public static class SubtitleReasons
{
    public const string DownloadFailed = "DownloadFailed";
    public const string UploadFailed = "UploadFailed";
}

/// <summary>Il corpo degli errori.</summary>
public sealed record SubtitleErrorDto([property: JsonPropertyName("Reason")] string Reason);

/// <summary>Corpo di POST Subtitles/{itemId}/Download.</summary>
public sealed class DownloadSubtitleRequest
{
    [JsonPropertyName("SubtitleId")]
    public string? SubtitleId { get; set; }
}

/// <summary>Corpo di POST Subtitles/{itemId}/Upload; Data è base64 standard.</summary>
public sealed class UploadSubtitleRequest
{
    [JsonPropertyName("Language")]
    public string? Language { get; set; }

    [JsonPropertyName("Format")]
    public string? Format { get; set; }

    [JsonPropertyName("IsForced")]
    public bool IsForced { get; set; }

    [JsonPropertyName("IsHearingImpaired")]
    public bool IsHearingImpaired { get; set; }

    [JsonPropertyName("Data")]
    public string? Data { get; set; }
}
