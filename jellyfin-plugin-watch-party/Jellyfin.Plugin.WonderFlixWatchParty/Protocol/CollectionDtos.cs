using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Una collezione in GET Collections (spec K §7.1): gli id nel formato di Jellyfin ("N").</summary>
public sealed record CollectionEntry(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("SortName")] string SortName,
    [property: JsonPropertyName("PrimaryImageTag")] string? PrimaryImageTag,
    [property: JsonPropertyName("DateCreated")] DateTime DateCreated,
    [property: JsonPropertyName("ItemIds")] IReadOnlyList<string> ItemIds);

/// <summary>Risposta di GET Collections.</summary>
public sealed record CollectionsResponse(
    [property: JsonPropertyName("Collections")] IReadOnlyList<CollectionEntry> Collections);
