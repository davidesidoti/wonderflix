using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un passo di un'operazione dello spazio, con lo stato e il motivo (spec U §6.1).</summary>
public sealed record SpaceStepDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Detail")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Detail,
    [property: JsonPropertyName("Done")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? Done,
    [property: JsonPropertyName("Waiting")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] int? Waiting);

/// <summary>Un'operazione dello spazio: i passi, lo stato e i byte attesi e liberati (spec U §6.1 e §6.2).</summary>
public sealed record SpaceOperationDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Kind")] string Kind,
    [property: JsonPropertyName("Key")] string Key,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Auto")] bool Auto,
    [property: JsonPropertyName("StartedAt")] DateTimeOffset StartedAt,
    [property: JsonPropertyName("EndedAt")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? EndedAt,
    [property: JsonPropertyName("EstimatedFreedBytes")] long EstimatedFreedBytes,
    [property: JsonPropertyName("PendingBytes")] long PendingBytes,
    [property: JsonPropertyName("QuotaBeforeBytes")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] long? QuotaBeforeBytes,
    [property: JsonPropertyName("QuotaAfterBytes")][property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] long? QuotaAfterBytes,
    [property: JsonPropertyName("Steps")] IReadOnlyList<SpaceStepDto> Steps);
