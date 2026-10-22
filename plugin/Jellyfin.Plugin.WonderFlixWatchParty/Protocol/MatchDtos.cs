using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Fasi di una sala del match (spec P §6.1).</summary>
public static class MatchPhases
{
    public const string Waiting = "Waiting";
    public const string Voting = "Voting";
    public const string Closed = "Closed";
}

/// <summary>Perché una sala si è chiusa (spec P §6.1).</summary>
public static class MatchClosedReasons
{
    /// <summary>È uscito chi l'ha aperta (Leave, o 60 s senza sessioni).</summary>
    public const string CreatorLeft = "CreatorLeft";

    /// <summary>Un'ora senza voti né ingressi.</summary>
    public const string Inactive = "Inactive";

    /// <summary>Chi l'ha aperta ha avviato il party: c'è PartyGroupId.</summary>
    public const string PartyStarted = "PartyStarted";
}

/// <summary>I motivi dei 409 degli endpoint del match (spec P §6.4), nel corpo {Reason}.</summary>
public static class MatchReasons
{
    public const string InAnotherRoom = "InAnotherRoom";
    public const string NotMember = "NotMember";
    public const string NotCreator = "NotCreator";
    public const string Started = "Started";
    public const string Closed = "Closed";
    public const string Full = "Full";
    public const string NotInvited = "NotInvited";
    public const string NotEnoughMembers = "NotEnoughMembers";
    public const string NotStarted = "NotStarted";
    public const string NotNext = "NotNext";
    public const string NotFinished = "NotFinished";
    public const string NotYourParty = "NotYourParty";
}

/// <summary>Un membro della sala: quanti voti ha dato, mai quali.</summary>
public sealed record MatchMemberDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Voted")] int Voted);

/// <summary>Un quasi match (spec P §6.3): quanti sì su quanti membri.</summary>
public sealed record MatchNearMatchDto(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Yes")] int Yes,
    [property: JsonPropertyName("Of")] int Of);

/// <summary>
/// Lo stato della sala (spec P §6.4): nelle risposte e in MatchUpdated.
/// Mai i voti dei singoli.
/// </summary>
public sealed record MatchStateDto(
    [property: JsonPropertyName("RoomId")] string RoomId,
    [property: JsonPropertyName("Rev")] long Rev,
    [property: JsonPropertyName("Phase")] string Phase,
    [property: JsonPropertyName("CreatorId")] string CreatorId,
    [property: JsonPropertyName("CreatorName")] string CreatorName,
    [property: JsonPropertyName("Members")] IReadOnlyList<MatchMemberDto> Members,
    [property: JsonPropertyName("Stack")] IReadOnlyList<string> Stack,
    [property: JsonPropertyName("Matches")] IReadOnlyList<string> Matches,
    [property: JsonPropertyName("NearMatches")] IReadOnlyList<MatchNearMatchDto> NearMatches,
    [property: JsonPropertyName("ClosedReason")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? ClosedReason,
    [property: JsonPropertyName("PartyGroupId")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PartyGroupId);

/// <summary>Il corpo di un 409 del match.</summary>
public sealed record MatchErrorDto(
    [property: JsonPropertyName("Reason")] string Reason,
    [property: JsonPropertyName("RoomId")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? RoomId = null);

/// <summary>Corpo di POST Match/{roomId}/Start: i filtri, con i valori dell'app.</summary>
public sealed class MatchStartRequest
{
    /// <summary>"movies", "series" o "both".</summary>
    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    /// <summary>"any", "90" o "120" (minuti, solo per i film).</summary>
    [JsonPropertyName("Duration")]
    public string? Duration { get; set; }

    /// <summary>Il nome di un genere; vuoto o assente per tutti.</summary>
    [JsonPropertyName("Genre")]
    public string? Genre { get; set; }

    /// <summary>"any", "good" (7 o più) o "bad" (5 o meno); assente vale "any".</summary>
    [JsonPropertyName("Rating")]
    public string? Rating { get; set; }
}

/// <summary>Corpo di POST Match/{roomId}/Votes.</summary>
public sealed class MatchVoteRequest
{
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("Yes")]
    public bool? Yes { get; set; }
}

/// <summary>Corpo di POST Match/{roomId}/Party.</summary>
public sealed class MatchPartyRequest
{
    [JsonPropertyName("GroupId")]
    public string? GroupId { get; set; }
}
