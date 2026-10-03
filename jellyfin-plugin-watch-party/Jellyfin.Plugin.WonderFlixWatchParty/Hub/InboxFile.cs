using System.Text.Json.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di inbox.json (spec G §6.1). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="InboxBook.FromFile"/>.
/// </summary>
public sealed class InboxFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, InboxFileUser?>? Users { get; set; } = [];
}

/// <summary>La cassetta di un utente, nel file.</summary>
public sealed class InboxFileUser
{
    /// <summary>Il prossimo Seq da dare.</summary>
    [JsonPropertyName("NextSeq")]
    public long NextSeq { get; set; } = 1;

    [JsonPropertyName("Entries")]
    public List<InboxEntry?>? Entries { get; set; } = [];
}
