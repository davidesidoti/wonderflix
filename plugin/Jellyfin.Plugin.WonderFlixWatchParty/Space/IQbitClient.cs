namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Il client di qBittorrent (WebUI API v2), con il login gestito dentro (spec U §7.2).</summary>
public interface IQbitClient
{
    Task<IReadOnlyList<QbitTorrent>> GetTorrentsAsync(CancellationToken cancellationToken);

    /// <exception cref="QbitException"><see cref="QbitError.NotFound"/> se il torrent non c'è.</exception>
    Task<IReadOnlyList<QbitFile>> GetFilesAsync(string hash, CancellationToken cancellationToken);

    /// <exception cref="QbitException"><see cref="QbitError.NotFound"/> se il torrent non c'è.</exception>
    Task<IReadOnlyList<QbitTracker>> GetTrackersAsync(string hash, CancellationToken cancellationToken);

    /// <summary>Toglie i torrent, e con <paramref name="deleteFiles"/> anche i loro file dal disco; un elenco vuoto non chiama.</summary>
    Task DeleteAsync(IReadOnlyList<string> hashes, bool deleteFiles, CancellationToken cancellationToken);
}
