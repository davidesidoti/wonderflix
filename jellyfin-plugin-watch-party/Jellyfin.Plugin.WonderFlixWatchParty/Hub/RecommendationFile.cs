using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di recommendations.json (spec N §6.1): per ogni destinatario
/// (id in formato "N") i titoli consigliati con i loro mittenti. Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="RecommendationBook.FromFile"/>.
/// </summary>
public sealed class RecommendationFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, List<RecommendationFileTitle?>?>? Users { get; set; } = [];
}

/// <summary>Un titolo consigliato, nel file.</summary>
public sealed class RecommendationFileTitle
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("From")]
    public List<RecommendationFileSender?>? From { get; set; } = [];
}

/// <summary>Chi ha consigliato il titolo, nel file.</summary>
public sealed class RecommendationFileSender
{
    /// <summary>L'amico, in formato "N".</summary>
    [JsonPropertyName("UserId")]
    public string? UserId { get; set; }

    /// <summary>Il messaggio; manca se non c'è.</summary>
    [JsonPropertyName("Message")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Message { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }
}
