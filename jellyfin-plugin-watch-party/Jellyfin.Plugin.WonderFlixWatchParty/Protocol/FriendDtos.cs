using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Relazione tra chi cerca e un utente trovato (spec F §6.2).</summary>
public static class FriendRelations
{
    public const string None = "None";
    public const string Friend = "Friend";
    public const string Incoming = "Incoming";
    public const string Outgoing = "Outgoing";
}

/// <summary>Il party visibile in cui sta un amico (dal piano 12b; prima sempre null).</summary>
public sealed record FriendParty(
    [property: JsonPropertyName("GroupId")] string GroupId,
    [property: JsonPropertyName("Title")] string Title);

/// <summary>Un amico, con il suo stato.</summary>
public sealed record FriendEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Online")] bool Online,
    [property: JsonPropertyName("Party")] FriendParty? Party);

/// <summary>Chi ha mandato o ricevuto una richiesta in sospeso.</summary>
public sealed record PersonEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name);

/// <summary>Risposta di GET Friends.</summary>
public sealed record FriendsResponse(
    [property: JsonPropertyName("Friends")] IReadOnlyList<FriendEntry> Friends,
    [property: JsonPropertyName("Incoming")] IReadOnlyList<PersonEntry> Incoming,
    [property: JsonPropertyName("Outgoing")] IReadOnlyList<PersonEntry> Outgoing);

/// <summary>Un risultato di GET Users/Search.</summary>
public sealed record UserSearchResult(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Relation")] string Relation);
