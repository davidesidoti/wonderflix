using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Di quale titolo si chiede il trailer: un elemento della libreria (<c>ItemId</c>) oppure un titolo TMDB (<c>Type</c> "movie" o "tv" + <c>TmdbId</c>).</summary>
public sealed class TrailerSubjectRequest
{
    public string? ItemId { get; set; }

    public string? Type { get; set; }

    public int? TmdbId { get; set; }
}

/// <summary>C'è un trailer per questo titolo? <c>Name</c> è il titolo del video, se lo si conosce.</summary>
public sealed record TrailerInfoDto(
    [property: JsonPropertyName("Available")] bool Available,
    [property: JsonPropertyName("Name")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Name);

/// <summary>Il download di un trailer: <c>Key</c> serve per chiederne lo stato e il flusso; è null se il trailer non c'è.</summary>
public sealed record TrailerStatusDto(
    [property: JsonPropertyName("Key")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Key,
    [property: JsonPropertyName("State")] string State);
