using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi degli avvisi che non riguardano un gruppo (spec F §6.8).</summary>
public static class SocialEventTypes
{
    public const string FriendRequest = "FriendRequest";
    public const string FriendsChanged = "FriendsChanged";
    public const string PartyStarted = "PartyStarted";
    public const string PartyInvite = "PartyInvite";
}

/// <summary>
/// Avviso del plugin a un utente, fuori dal canale di un gruppo (spec F
/// §6.8). Non ha Id: le app 0.5.x lo scartano (anche quando ha il GroupId
/// del loro gruppo).
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

    [JsonPropertyName("GroupId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? GroupId { get; init; }

    /// <summary>Nome del gruppo SyncPlay ("Host · Titolo").</summary>
    [JsonPropertyName("Name")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Name { get; init; }

    [JsonPropertyName("Mode")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Mode { get; init; }

    public static SocialEvent FriendRequest(string fromUserId, string fromName) =>
        new() { Type = SocialEventTypes.FriendRequest, FromUserId = fromUserId, FromName = fromName };

    public static SocialEvent FriendsChanged() => new() { Type = SocialEventTypes.FriendsChanged };

    public static SocialEvent PartyStarted(string groupId, string name, string mode) =>
        new() { Type = SocialEventTypes.PartyStarted, GroupId = groupId, Name = name, Mode = mode };

    public static SocialEvent PartyInvite(string groupId, string name, string fromName) =>
        new() { Type = SocialEventTypes.PartyInvite, GroupId = groupId, Name = name, FromName = fromName };
}
