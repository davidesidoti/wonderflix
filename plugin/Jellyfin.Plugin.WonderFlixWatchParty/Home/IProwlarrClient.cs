namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Una ricerca su Prowlarr, sempre per titolo (mai per id). <paramref name="Type"/> è "search", "tvsearch" o "movie".
/// <paramref name="Season"/> ed <paramref name="Episode"/> si mandano solo se ci sono.
/// </summary>
public sealed record ProwlarrQuery(
    string Type,
    string Query,
    int? Season,
    int? Episode,
    IReadOnlyList<int> IndexerIds,
    IReadOnlyList<int> Categories);

/// <summary>Prowlarr (API v1): le ricerche negli indexer.</summary>
public interface IProwlarrClient
{
    /// <summary>Cerca le release; gli errori sono <see cref="ArrException"/>, come per <see cref="IArrClient"/>.</summary>
    Task<IReadOnlyList<ProwlarrRelease>> SearchAsync(ProwlarrQuery query, CancellationToken cancellationToken);
}
