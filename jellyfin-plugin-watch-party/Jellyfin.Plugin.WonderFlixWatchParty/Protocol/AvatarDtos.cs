using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un utente in GET Users/Avatars (spec K §7.2): l'id nel formato di Jellyfin ("N").</summary>
public sealed record AvatarEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("ImageTag")] string? ImageTag);

/// <summary>Risposta di GET Users/Avatars.</summary>
public sealed record AvatarsResponse(
    [property: JsonPropertyName("Users")] IReadOnlyList<AvatarEntry> Users);
