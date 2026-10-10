using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Risposta di GET e POST Home/Layout (spec M §7.2): la Home dell'admin.
/// Rows null (o assente: Jellyfin può non scrivere i null) se mai impostata.
/// </summary>
public sealed record HomeLayoutDto([property: JsonPropertyName("Rows")] IReadOnlyList<string>? Rows);

/// <summary>Corpo di POST Home/Layout: Rows null torna all'ordine predefinito, vuoto spegne tutte le righe.</summary>
public sealed class HomeLayoutRequest
{
    [JsonPropertyName("Rows")]
    public List<string?>? Rows { get; set; }
}
