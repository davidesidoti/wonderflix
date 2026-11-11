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
}
