using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Fasi di una votazione di fine party (spec Q).</summary>
public static class RatingPhases
{
    public const string Voting = "Voting";
    public const string Revealed = "Revealed";
}

/// <summary>Cosa ha fatto un presente nella votazione.</summary>
public static class RatingVoterStatuses
{
    public const string Waiting = "Waiting";
    public const string Voted = "Voted";
    public const string Skipped = "Skipped";
}

/// <summary>I motivi dei 409 degli endpoint dei voti, nel corpo {Reason}.</summary>
public static class RatingReasons
{
    public const string NotMember = "NotMember";
    public const string NotCreator = "NotCreator";
    public const string Closed = "Closed";
}

/// <summary>Il voto di chi guarda (Mine): il punteggio e il commento, se c'è.</summary>
public sealed record RatingScoreDto(
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Comment"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Comment);

/// <summary>Un presente nella votazione e il suo stato (mai il voto).</summary>
public sealed record RatingVoterDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Status")] string Status);

/// <summary>Un voto scoperto, solo in Revealed.</summary>
public sealed record RatingResultDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Comment"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Comment);

/// <summary>Lo stato della votazione visto da un destinatario; Results e Average solo in Revealed.</summary>
public sealed record RatingRoundDto(
    [property: JsonPropertyName("GroupId")] string GroupId,
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Phase")] string Phase,
    [property: JsonPropertyName("Rev")] long Rev,
    [property: JsonPropertyName("EndsAt")] DateTimeOffset EndsAt,
    [property: JsonPropertyName("CanReveal")] bool CanReveal,
    [property: JsonPropertyName("Mine"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] RatingScoreDto? Mine,
    [property: JsonPropertyName("Voters")] IReadOnlyList<RatingVoterDto> Voters,
    [property: JsonPropertyName("Results"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<RatingResultDto>? Results,
    [property: JsonPropertyName("Average"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] double? Average);

/// <summary>Nessuna votazione: si scrive {}.</summary>
public sealed record RatingRoundEmptyDto();

/// <summary>Il corpo dei 409.</summary>
public sealed record RatingErrorDto([property: JsonPropertyName("Reason")] string Reason);

/// <summary>Il voto di un amico nella scheda.</summary>
public sealed record FriendRatingDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Comment"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Comment,
    [property: JsonPropertyName("UpdatedAt")] DateTimeOffset UpdatedAt);

/// <summary>GET Ratings: la scheda di un titolo.</summary>
public sealed record ItemRatingsDto(
    [property: JsonPropertyName("CanRate")] bool CanRate,
    [property: JsonPropertyName("Mine"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] RatingScoreDto? Mine,
    [property: JsonPropertyName("Average"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] double? Average,
    [property: JsonPropertyName("Count")] int Count,
    [property: JsonPropertyName("Friends")] IReadOnlyList<FriendRatingDto> Friends);

/// <summary>Un commento nell'elenco admin.</summary>
public sealed record AdminCommentDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("UserName")] string UserName,
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Score")] int Score,
    [property: JsonPropertyName("Comment")] string Comment,
    [property: JsonPropertyName("UpdatedAt")] DateTimeOffset UpdatedAt);

/// <summary>Una pagina di commenti; Next è l'UpdatedAt dell'ultima voce, assente a fine elenco.</summary>
public sealed record AdminCommentsDto(
    [property: JsonPropertyName("Items")] IReadOnlyList<AdminCommentDto> Items,
    [property: JsonPropertyName("Next"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? Next);

/// <summary>Corpo di POST Ratings/Rounds.</summary>
public sealed class OpenRatingRoundRequest
{
    [JsonPropertyName("GroupId")]
    public string? GroupId { get; set; }

    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }
}

/// <summary>Corpo di Vote e PUT Ratings.</summary>
public sealed class RateRequest
{
    [JsonPropertyName("Score")]
    public int? Score { get; set; }

    [JsonPropertyName("Comment")]
    public string? Comment { get; set; }
}
