using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di ratings.json (spec Q §6): per titolo (id "N") i voti degli
/// utenti. Tutto nullable: un file rovinato si scopre in
/// <see cref="RatingBook.FromFile"/>.
/// </summary>
public sealed class RatingFile
{
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Items")]
    public Dictionary<string, List<RatingFileEntry?>?>? Items { get; set; } = [];
}

/// <summary>Un voto, nel file.</summary>
public sealed class RatingFileEntry
{
    [JsonPropertyName("UserId")]
    public string? UserId { get; set; }

    [JsonPropertyName("Score")]
    public int Score { get; set; }

    [JsonPropertyName("Comment")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Comment { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("UpdatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
