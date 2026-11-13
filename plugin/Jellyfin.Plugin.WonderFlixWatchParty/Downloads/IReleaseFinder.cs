using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Chi cerca le release: Prowlarr (poi il parse di Sonarr/Radarr) o la ricerca di Sonarr/Radarr stessi.</summary>
public enum SearchEngine
{
    Prowlarr,
    Arr,
}

/// <summary>
/// Quello che una ricerca ha trovato. <paramref name="WrongTitle"/> sono le release che il parse attribuisce ad altro:
/// non sono fra <paramref name="Releases"/>. <paramref name="Engine"/> è chi ha cercato davvero.
/// </summary>
public sealed record FinderResult(IReadOnlyList<ArrRelease?> Releases, IReadOnlyList<ArrRelease> WrongTitle, SearchEngine Engine);

/// <summary>
/// Com'è andato un grab: preso (<see cref="Grabbed"/>), preso ma in attesa per un ritardo del profilo (<see cref="Pending"/>),
/// scartato dalle regole di Sonarr/Radarr (<see cref="RuleRefused"/>), rifiutato dal client (<see cref="ClientRefused"/>), o
/// messo direttamente in qBittorrent (<see cref="Direct"/>).
/// </summary>
public enum GrabKind
{
    Grabbed,
    Pending,
    RuleRefused,
    ClientRefused,
    Direct,
}

/// <summary>L'esito di un grab: per <see cref="GrabKind.RuleRefused"/> il primo motivo, per <see cref="GrabKind.Direct"/> l'hash del torrent.</summary>
public sealed record GrabResult(GrabKind Kind, string? Reason, string? Hash);

/// <summary>La ricerca delle release per un titolo da scaricare.</summary>
public interface IReleaseFinder
{
    /// <summary>Prowlarr è configurato: la ricerca di default passa da lì.</summary>
    bool UsesProwlarr { get; }

    /// <summary>
    /// Cerca le release di <paramref name="key"/>. Con <see cref="SearchEngine.Arr"/>, o se Prowlarr non è configurato,
    /// usa la ricerca di Sonarr/Radarr (con <paramref name="arrTimeout"/>); gli errori sono <see cref="ArrException"/>.
    /// </summary>
    Task<FinderResult> SearchAsync(DownloadKey key, SearchEngine engine, CancellationToken cancellationToken, TimeSpan? arrTimeout = null);

    /// <summary>
    /// Scarica la release: per guid come sempre se viene dalla ricerca di Sonarr/Radarr, con il push se viene da Prowlarr. Un
    /// download <paramref name="intentional"/> che il push scarta solo per file, coda o monitoraggio va direttamente in qBittorrent;
    /// con <paramref name="outsideProfile"/> (solo l'admin, mai il giro) anche se lo scarta per una qualità fuori dal profilo.
    /// Un push approvato senza il grab nella cronologia di Sonarr/Radarr è <see cref="GrabKind.ClientRefused"/>.
    /// Gli <see cref="ArrException"/> di Sonarr/Radarr (5xx = rifiuto del client) e i <see cref="Space.QbitException"/> passano.
    /// </summary>
    Task<GrabResult> GrabAsync(ArrKind service, ArrRelease release, bool intentional, CancellationToken cancellationToken, bool outsideProfile = false);

    /// <summary>
    /// Mette la release di Prowlarr direttamente in qBittorrent, nella categoria del client di Sonarr/Radarr, senza push; l'hash
    /// del torrent. Gli errori sono <see cref="Space.QbitException"/> (e <see cref="ArrException"/> leggendo i client).
    /// </summary>
    Task<string> AddDirectAsync(ArrKind service, ArrRelease release, CancellationToken cancellationToken);
}
