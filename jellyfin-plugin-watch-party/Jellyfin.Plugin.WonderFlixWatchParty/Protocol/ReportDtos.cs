using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>I tipi di segnalazione (spec R).</summary>
public static class ReportTypes
{
    public const string Subtitles = "Subtitles";
    public const string Metadata = "Metadata";
    public const string AudioVideo = "AudioVideo";
    public const string Other = "Other";

    public static bool IsValid(string? type) => type is Subtitles or Metadata or AudioVideo or Other;
}

/// <summary>Come un admin chiude una segnalazione.</summary>
public static class ReportOutcomes
{
    public const string Fixed = "Fixed";
    public const string CannotFix = "CannotFix";

    public static bool IsValid(string? outcome) => outcome is Fixed or CannotFix;
}

/// <summary>I motivi degli errori con corpo degli endpoint delle segnalazioni, nel corpo {Reason}.</summary>
public static class ReportReasons
{
    public const string LimitReached = "LimitReached";
    public const string Closed = "Closed";
}

/// <summary>
/// Una segnalazione aperta. I nomi si leggono dalla libreria a ogni risposta; per un
/// titolo che non c'è più ItemName, TitleName e ItemType sono vuoti e TitleId è ItemId.
/// </summary>
public sealed record ReportDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Type")] string Type,
    [property: JsonPropertyName("Note"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Note,
    [property: JsonPropertyName("CreatedAt")] DateTimeOffset CreatedAt,
    [property: JsonPropertyName("UpdatedAt")] DateTimeOffset UpdatedAt,
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("UserName")] string UserName,
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("ItemType")] string ItemType,
    [property: JsonPropertyName("ItemName")] string ItemName,
    [property: JsonPropertyName("TitleId")] string TitleId,
    [property: JsonPropertyName("TitleName")] string TitleName,
    [property: JsonPropertyName("SeasonNumber"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? SeasonNumber,
    [property: JsonPropertyName("EpisodeNumber"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? EpisodeNumber);

/// <summary>GET Reports e GET Reports/Mine.</summary>
public sealed record ReportListDto([property: JsonPropertyName("Items")] IReadOnlyList<ReportDto> Items);

/// <summary>Il corpo degli errori.</summary>
public sealed record ReportErrorDto([property: JsonPropertyName("Reason")] string Reason);

/// <summary>Corpo di POST Reports.</summary>
public sealed class CreateReportRequest
{
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    [JsonPropertyName("Note")]
    public string? Note { get; set; }
}

/// <summary>Corpo di POST Reports/{id}/Resolve.</summary>
public sealed class ResolveReportRequest
{
    [JsonPropertyName("Outcome")]
    public string? Outcome { get; set; }

    [JsonPropertyName("Note")]
    public string? Note { get; set; }
}
