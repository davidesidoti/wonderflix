using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di activity.json (spec O §6.1 e §6.4, piano 21a decisione 1):
/// chi ha spento "Mostra agli amici cosa guardo" e, per ogni utente (id in
/// formato "N"), i film e le serie guardati. Tutto nullable: un file scritto
/// a mano o rovinato si scopre in <see cref="ActivityBook.FromFile"/>.
/// </summary>
public sealed class ActivityFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    /// <summary>Chi non mostra cosa guarda, in formato "N"; chi non c'è mostra.</summary>
    [JsonPropertyName("Hidden")]
    public List<string?>? Hidden { get; set; } = [];

    [JsonPropertyName("Users")]
    public Dictionary<string, List<ActivityFileView?>?>? Users { get; set; } = [];
}

/// <summary>Una visione, nel file.</summary>
public sealed class ActivityFileView
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("WatchedAt")]
    public DateTimeOffset WatchedAt { get; set; }
}
