using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Risposta di Join: lo storico della chat, dal messaggio più vecchio.</summary>
public sealed record JoinResponse(
    [property: JsonPropertyName("Messages")] IReadOnlyList<StampedEvent> Messages);
