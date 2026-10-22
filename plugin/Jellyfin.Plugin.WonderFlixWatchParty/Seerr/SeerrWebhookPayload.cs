using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// Il corpo del webhook, dal modello della pagina del plugin (spec I §7.1):
/// testi già sostituiti da Seerr; "extra" viene dalla chiave speciale
/// "{{extra}}".
/// </summary>
public sealed class SeerrWebhookPayload
{
    public string? Secret { get; set; }

    [JsonPropertyName("notification_type")]
    public string? NotificationType { get; set; }

    public string? Subject { get; set; }

    [JsonPropertyName("request_id")]
    public string? RequestId { get; set; }

    [JsonPropertyName("media_type")]
    public string? MediaType { get; set; }

    [JsonPropertyName("media_tmdbid")]
    public string? MediaTmdbId { get; set; }

    [JsonPropertyName("media_jellyfinMediaId")]
    public string? MediaJellyfinMediaId { get; set; }

    [JsonPropertyName("requestedBy_jellyfinUserId")]
    public string? RequestedByJellyfinUserId { get; set; }

    [JsonPropertyName("requestedBy_username")]
    public string? RequestedByUsername { get; set; }

    public List<SeerrWebhookExtra>? Extra { get; set; }
}

public sealed class SeerrWebhookExtra
{
    public string? Name { get; set; }

    public string? Value { get; set; }
}
