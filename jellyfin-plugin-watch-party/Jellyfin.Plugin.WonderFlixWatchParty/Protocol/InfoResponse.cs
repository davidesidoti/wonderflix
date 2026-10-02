using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Risposta di GET /WonderFlixWatchParty/Info.</summary>
public sealed record InfoResponse(
    [property: JsonPropertyName("Version")] string Version,
    [property: JsonPropertyName("Protocol")] int Protocol);
