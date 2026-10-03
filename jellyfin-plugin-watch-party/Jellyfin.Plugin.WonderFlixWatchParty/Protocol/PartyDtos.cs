using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Modalità di un party (spec F §6.4). Esatte, con la maiuscola.</summary>
public static class PartyModes
{
    public const string Public = "Public";
    public const string Friends = "Friends";
    public const string Private = "Private";

    public static bool IsValid(string? mode) => mode is Public or Friends or Private;
}

/// <summary>Corpo di POST Parties/{groupId}.</summary>
public sealed class RegisterPartyRequest
{
    [JsonPropertyName("Mode")]
    public string? Mode { get; set; }
}

/// <summary>Risposta della registrazione: il codice, solo per i privati.</summary>
public sealed record RegisterPartyResponse(
    [property: JsonPropertyName("Code")] string? Code);

/// <summary>Un party dell'elenco (GET Parties).</summary>
public sealed record PartySummary(
    [property: JsonPropertyName("GroupId")] string GroupId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Participants")] IReadOnlyList<string> Participants,
    [property: JsonPropertyName("Mode")] string Mode);

/// <summary>Modalità e codice del party (GET Parties/{groupId}, solo per i partecipanti).</summary>
public sealed record PartyDetails(
    [property: JsonPropertyName("Mode")] string Mode,
    [property: JsonPropertyName("Code")] string? Code);

/// <summary>Corpo di POST Parties/Join.</summary>
public sealed class JoinByCodeRequest
{
    [JsonPropertyName("Code")]
    public string? Code { get; set; }
}

/// <summary>Il gruppo del codice.</summary>
public sealed record JoinByCodeResponse(
    [property: JsonPropertyName("GroupId")] string GroupId);

/// <summary>Corpo di POST Parties/{groupId}/Invites.</summary>
public sealed class InviteRequest
{
    [JsonPropertyName("UserIds")]
    public List<string>? UserIds { get; set; }
}
