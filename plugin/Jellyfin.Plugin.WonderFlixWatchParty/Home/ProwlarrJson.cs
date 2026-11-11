namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una release di <c>GET /api/v1/search</c> di Prowlarr (solo i campi che servono).</summary>
public sealed class ProwlarrRelease
{
    public string? Guid { get; set; }

    public int IndexerId { get; set; }

    public string? Indexer { get; set; }

    public string? Title { get; set; }

    public long Size { get; set; }

    public int? Seeders { get; set; }

    /// <summary>Il .torrent da scaricare tramite Prowlarr; null per chi dà solo il magnet.</summary>
    public string? DownloadUrl { get; set; }

    public string? MagnetUrl { get; set; }

    /// <summary>"torrent" o "usenet".</summary>
    public string? Protocol { get; set; }

    public DateTimeOffset? PublishDate { get; set; }

    public string? InfoUrl { get; set; }
}
