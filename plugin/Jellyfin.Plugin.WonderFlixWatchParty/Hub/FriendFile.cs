using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di friends.json (spec F §6.1). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="FriendGraph.FromFile"/>.
/// </summary>
public sealed class FriendFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    /// <summary>Coppie di amici: ogni voce ha esattamente due id.</summary>
    [JsonPropertyName("Friendships")]
    public List<string[]>? Friendships { get; set; } = [];

    [JsonPropertyName("Requests")]
    public List<FriendFileRequest>? Requests { get; set; } = [];
}

/// <summary>Una richiesta in sospeso, nel file.</summary>
public sealed class FriendFileRequest
{
    [JsonPropertyName("From")]
    public string? From { get; set; }

    [JsonPropertyName("To")]
    public string? To { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }
}
