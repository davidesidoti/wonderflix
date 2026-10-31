using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un tipo di notifica push e se l'utente lo riceve.</summary>
public sealed record NotificationTypeDto(
    [property: JsonPropertyName("Type")] string Type,
    [property: JsonPropertyName("Enabled")] bool Enabled);

/// <summary>Risposta di GET Notifications: la chiave VAPID e i tipi che chi chiama può ricevere, in ordine.</summary>
public sealed record NotificationsResponse(
    [property: JsonPropertyName("VapidPublicKey")] string VapidPublicKey,
    [property: JsonPropertyName("Types")] IReadOnlyList<NotificationTypeDto> Types);

/// <summary>Corpo di POST Notifications/Subscriptions: l'iscrizione del browser (PushSubscription.toJSON) e la lingua.</summary>
public sealed class SubscribeRequest
{
    [JsonPropertyName("Endpoint")]
    public string? Endpoint { get; set; }

    [JsonPropertyName("P256dh")]
    public string? P256dh { get; set; }

    [JsonPropertyName("Auth")]
    public string? Auth { get; set; }

    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}
