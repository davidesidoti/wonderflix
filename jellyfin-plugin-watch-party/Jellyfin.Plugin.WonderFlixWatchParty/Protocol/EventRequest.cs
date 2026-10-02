using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Corpo di POST …/Groups/{groupId}/Events: un evento mandato dall'app.</summary>
public sealed class EventRequest
{
    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    /// <summary>Per Action: Pause, Unpause, Seek, NextItem, NewQueue.</summary>
    [JsonPropertyName("Action")]
    public string? Action { get; set; }

    /// <summary>Per Action Seek.</summary>
    [JsonPropertyName("PositionTicks")]
    public long? PositionTicks { get; set; }

    [JsonPropertyName("Text")]
    public string? Text { get; set; }

    [JsonPropertyName("Reaction")]
    public string? Reaction { get; set; }
}
