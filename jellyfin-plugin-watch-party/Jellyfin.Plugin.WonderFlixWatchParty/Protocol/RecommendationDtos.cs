using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un amico nel pannello "Consiglia a…" (spec N §6.2).</summary>
public sealed record RecommendationTarget(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Online")] bool Online,
    [property: JsonPropertyName("CanSee")] bool CanSee);

/// <summary>Risposta di GET Recommendations/Targets.</summary>
public sealed record RecommendationTargetsResponse(
    [property: JsonPropertyName("Friends")] IReadOnlyList<RecommendationTarget> Friends);

/// <summary>Corpo di POST Recommendations.</summary>
public sealed class RecommendRequest
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    /// <summary>Gli amici, in formato "N".</summary>
    [JsonPropertyName("To")]
    public List<string?>? To { get; set; }

    [JsonPropertyName("Message")]
    public string? Message { get; set; }
}

/// <summary>Risposta di POST Recommendations: a quanti amici è arrivato.</summary>
public sealed record RecommendResponse(
    [property: JsonPropertyName("Sent")] int Sent);

/// <summary>Chi ha consigliato un titolo, in GET Recommendations.</summary>
public sealed record RecommendationFrom(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Message"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Message,
    [property: JsonPropertyName("CreatedAt")] DateTimeOffset CreatedAt);

/// <summary>Un titolo consigliato, in GET Recommendations.</summary>
public sealed record RecommendationItem(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("From")] IReadOnlyList<RecommendationFrom> From);

/// <summary>Risposta di GET Recommendations: i titoli dalla data più recente.</summary>
public sealed record RecommendationsResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<RecommendationItem> Items);
