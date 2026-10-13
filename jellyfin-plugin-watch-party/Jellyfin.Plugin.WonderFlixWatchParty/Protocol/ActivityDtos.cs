using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Cosa sta guardando un amico (spec O §6.2): il film o l'episodio; per un
/// episodio anche serie, stagione e numero, ognuno assente se Jellyfin non
/// lo conosce.
/// </summary>
public sealed record FriendNowPlaying(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("SeriesId")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SeriesId,
    [property: JsonPropertyName("SeriesName")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SeriesName,
    [property: JsonPropertyName("Season")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? Season,
    [property: JsonPropertyName("Episode")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? Episode);

/// <summary>Risposta di GET Friends/{userId}/NowPlaying (spec O §6.5): l'elemento e dove è arrivato l'amico.</summary>
public sealed record FriendPosition(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("PositionTicks")] long PositionTicks);

/// <summary>Corpo di PUT Activity/Settings.</summary>
public sealed class ActivitySettings
{
    [JsonPropertyName("ShareActivity")]
    public bool? ShareActivity { get; set; }
}

/// <summary>Risposta di GET Activity/Settings.</summary>
public sealed record ActivitySettingsResponse(
    [property: JsonPropertyName("ShareActivity")] bool ShareActivity);

/// <summary>Un amico che ha visto il titolo, e quando l'ultima volta.</summary>
public sealed record FriendWatcher(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("WatchedAt")] DateTimeOffset WatchedAt);

/// <summary>Un titolo della riga "Visti dagli amici", con chi l'ha visto dal più recente.</summary>
public sealed record FriendsWatchedItem(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("By")] IReadOnlyList<FriendWatcher> By);

/// <summary>Risposta di GET Activity/FriendsWatched (spec O §6.6).</summary>
public sealed record FriendsWatchedResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<FriendsWatchedItem> Items);
