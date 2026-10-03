using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi degli avvisi che non riguardano un gruppo (spec F §6.8).</summary>
public static class SocialEventTypes
{
    public const string FriendRequest = "FriendRequest";
    public const string FriendsChanged = "FriendsChanged";
}

/// <summary>
/// Avviso del plugin a un utente, fuori dal canale di un gruppo (spec F
/// §6.8). Non ha Id né GroupId: le app 0.5.x lo scartano.
/// </summary>
public sealed class SocialEvent
{
    [JsonPropertyName("Protocol")]
    public int Protocol { get; init; } = WatchPartyProtocol.Version;

    [JsonPropertyName("Type")]
    public required string Type { get; init; }

    [JsonPropertyName("FromUserId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromUserId { get; init; }

    [JsonPropertyName("FromName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromName { get; init; }

    public static SocialEvent FriendRequest(string fromUserId, string fromName) =>
        new() { Type = SocialEventTypes.FriendRequest, FromUserId = fromUserId, FromName = fromName };

    public static SocialEvent FriendsChanged() => new() { Type = SocialEventTypes.FriendsChanged };
}
