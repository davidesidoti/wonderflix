using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di reports.json (spec R §3): le sole segnalazioni aperte. Tutto
/// nullable: un file rovinato si scopre in <see cref="ReportBook.FromFile"/>.
/// </summary>
public sealed class ReportFile
{
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Reports")]
    public List<ReportFileEntry?>? Reports { get; set; } = [];
}

/// <summary>Una segnalazione, nel file (id in formato "N").</summary>
public sealed class ReportFileEntry
{
    [JsonPropertyName("Id")]
    public string? Id { get; set; }

    [JsonPropertyName("UserId")]
    public string? UserId { get; set; }

    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    [JsonPropertyName("Note")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Note { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("UpdatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
