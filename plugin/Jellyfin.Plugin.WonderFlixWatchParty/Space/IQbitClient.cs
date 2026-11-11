namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Il client di qBittorrent (WebUI API v2), con il login gestito dentro (spec U §7.2).</summary>
public interface IQbitClient
{
    Task<IReadOnlyList<QbitTorrent>> GetTorrentsAsync(CancellationToken cancellationToken);

    /// <exception cref="QbitException"><see cref="QbitError.NotFound"/> se il torrent non c'è.</exception>
    Task<IReadOnlyList<QbitFile>> GetFilesAsync(string hash, CancellationToken cancellationToken);

    /// <exception cref="QbitException"><see cref="QbitError.NotFound"/> se il torrent non c'è.</exception>
    Task<IReadOnlyList<QbitTracker>> GetTrackersAsync(string hash, CancellationToken cancellationToken);

    /// <summary>Il registro normale di qBittorrent (senza info, avvisi e critici), con l'ora in secondi.</summary>
    Task<IReadOnlyList<QbitLogEntry>> GetLogAsync(CancellationToken cancellationToken);

    /// <summary>Toglie i torrent, e con <paramref name="deleteFiles"/> anche i loro file dal disco; un elenco vuoto non chiama.</summary>
    Task DeleteAsync(IReadOnlyList<string> hashes, bool deleteFiles, CancellationToken cancellationToken);

    /// <summary>
    /// Aggiunge un torrent nella <paramref name="category"/>, con i tag <c>wonderflix</c> e uno unico. <paramref name="link"/> è
    /// un magnet o l'indirizzo del <c>.torrent</c> (lo scarica il plugin). Restituisce l'hash, minuscolo: dal magnet, o dal
    /// torrent nuovo col tag unico se appare entro un minuto.
    /// </summary>
    /// <exception cref="QbitException">qBittorrent rifiuta il torrent, il link non si scarica o il torrent non appare.</exception>
    Task<string> AddAsync(string link, string category, CancellationToken cancellationToken);
}
