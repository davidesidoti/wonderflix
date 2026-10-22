using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Un evento timbrato dal plugin (spec E §6.3): chi l'ha mandato lo dice la
/// sessione autenticata, mai il corpo della richiesta. È la risposta di
/// Events, una voce dello storico e il contenuto inoltrato ai client.
/// </summary>
public sealed class StampedEvent
{
    [JsonPropertyName("Protocol")]
    public int Protocol { get; init; } = WatchPartyProtocol.Version;

    /// <summary>Guid in formato "N": l'app lo usa per togliere i doppioni.</summary>
    [JsonPropertyName("Id")]
    public required string Id { get; init; }

    [JsonPropertyName("GroupId")]
    public required string GroupId { get; init; }

    [JsonPropertyName("Type")]
    public required string Type { get; init; }

    [JsonPropertyName("UserId")]
    public required string UserId { get; init; }

    [JsonPropertyName("UserName")]
    public required string UserName { get; init; }

    /// <summary>Ora UTC del server, es. 2026-10-02T21:14:03.512Z.</summary>
    [JsonPropertyName("SentAt")]
    public required string SentAt { get; init; }

    [JsonPropertyName("Action")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Action { get; init; }

    [JsonPropertyName("PositionTicks")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public long? PositionTicks { get; init; }

    [JsonPropertyName("Text")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Text { get; init; }

    [JsonPropertyName("Reaction")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reaction { get; init; }
}
