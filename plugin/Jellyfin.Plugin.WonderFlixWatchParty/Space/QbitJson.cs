using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Un torrent di <c>torrents/info</c> (spec U §7.2). Il JSON di qBittorrent è in snake_case.</summary>
public sealed class QbitTorrent
{
    [JsonPropertyName("hash")]
    public string? Hash { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    /// <summary>Byte del torrent.</summary>
    [JsonPropertyName("size")]
    public long Size { get; set; }

    /// <summary>Da 0 a 1.</summary>
    [JsonPropertyName("progress")]
    public double Progress { get; set; }

    [JsonPropertyName("ratio")]
    public double Ratio { get; set; }

    /// <summary>Secondi passati in seed.</summary>
    [JsonPropertyName("seeding_time")]
    public long SeedingTime { get; set; }

    /// <summary>Il tracker in uso; vuoto se non ce n'è uno attivo.</summary>
    [JsonPropertyName("tracker")]
    public string? Tracker { get; set; }

    [JsonPropertyName("state")]
    public string? State { get; set; }

    [JsonPropertyName("save_path")]
    public string? SavePath { get; set; }

    [JsonPropertyName("content_path")]
    public string? ContentPath { get; set; }
}

/// <summary>Un file di un torrent: <see cref="Name"/> è relativo a <c>save_path</c> (spec U §7.2).</summary>
public sealed class QbitFile
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("size")]
    public long Size { get; set; }
}

/// <summary>Un tracker di un torrent (spec U §7.2).</summary>
public sealed class QbitTracker
{
    [JsonPropertyName("url")]
    public string? Url { get; set; }
}
