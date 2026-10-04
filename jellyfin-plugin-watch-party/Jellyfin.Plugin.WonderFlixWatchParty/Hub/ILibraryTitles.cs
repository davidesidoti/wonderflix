namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un film o un episodio della libreria, riletto alla chiusura dell'ondata
/// (spec G §6.6). SeriesKey è la chiave con cui Jellyfin raggruppa gli
/// episodi della serie; Refreshed dice se i metadati sono arrivati (prima il
/// nome viene dal file e i numeri mancano).
/// </summary>
public sealed record LibraryTitle(
    Guid ItemId,
    bool IsMovie,
    string Name,
    int? Year,
    Guid SeriesId,
    string SeriesName,
    string SeriesKey,
    int? Season,
    int? Episode,
    IReadOnlyCollection<string> ExternalKeys,
    bool Refreshed)
{
    /// <summary>
    /// Gli id esterni della serie dell'episodio (TMDB, IMDb, TVDB, come
    /// ExternalKeys); vuoto per i film. Riconoscono la stessa serie dopo una
    /// cartella rinominata, quando SeriesKey cambia con l'id.
    /// </summary>
    public IReadOnlyCollection<string> SeriesExternalKeys { get; init; } = [];
}

/// <summary>La libreria come serve al riepilogo dei nuovi titoli (adattatore di ILibraryManager e IUserManager).</summary>
public interface ILibraryTitles
{
    /// <summary>Jellyfin sta scansionando la libreria.</summary>
    bool IsScanRunning { get; }

    /// <summary>Il titolo (film o episodio vero), riletto adesso; null se non c'è più o non è un titolo.</summary>
    LibraryTitle? Get(Guid itemId);

    /// <summary>
    /// L'utente segue la serie: è tra i suoi preferiti (La mia lista), oppure
    /// ha visto o iniziato un episodio che non è tra excludeEpisodes (quelli
    /// appena arrivati).
    /// </summary>
    bool FollowsSeries(Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes);
}
