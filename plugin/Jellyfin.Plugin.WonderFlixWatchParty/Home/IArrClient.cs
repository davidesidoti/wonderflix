namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Sonarr e Radarr (spec M §3). Gli errori sono <see cref="ArrException"/>.</summary>
public interface IArrClient
{
    /// <summary>Gli episodi delle serie seguite, con la serie; gli elementi possono essere null.</summary>
    Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken);

    /// <summary>I film seguiti con una data nel periodo; gli elementi possono essere null.</summary>
    Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken);

    /// <summary>Il film della libreria di Radarr con questo id TMDB (elenco vuoto se non c'è) (spec S §6.1).</summary>
    Task<IReadOnlyList<RadarrMovie?>> FindMoviesAsync(int tmdbId, CancellationToken cancellationToken);

    /// <summary>Il film per id TMDB anche se non è in libreria, con le date di uscita (spec S §6.1).</summary>
    Task<RadarrMovie> LookupMovieAsync(int tmdbId, CancellationToken cancellationToken);

    /// <summary>Tutte le serie di Sonarr, con id e prossima messa in onda (spec S §6.1).</summary>
    Task<IReadOnlyList<SonarrSeries?>> GetSeriesAsync(CancellationToken cancellationToken);

    /// <summary>Gli episodi di una serie di Sonarr (spec S §6.1).</summary>
    Task<IReadOnlyList<SonarrEpisode?>> GetSeriesEpisodesAsync(int seriesId, CancellationToken cancellationToken);

    /// <summary>Un episodio di Sonarr per id, con la serie (e il file, se c'è); 404 se non c'è (spec T §8.2).</summary>
    Task<SonarrEpisode> GetEpisodeAsync(int episodeId, CancellationToken cancellationToken);

    Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken);

    /// <summary>
    /// Le release trovate da una ricerca dal vivo (spec T §2). <paramref name="query"/> è la query di
    /// <c>release</c>: <c>movieId=12</c>, <c>episodeId=34</c> o <c>seriesId=5&amp;seasonNumber=2</c>.
    /// Può durare fino a <see cref="ArrClient.SearchTimeout"/>.
    /// </summary>
    Task<IReadOnlyList<ArrRelease?>> SearchReleasesAsync(ArrKind kind, string query, CancellationToken cancellationToken);

    /// <summary>Fa scaricare una release trovata da <see cref="SearchReleasesAsync"/> (spec T §2).</summary>
    Task GrabReleaseAsync(ArrKind kind, string guid, int indexerId, CancellationToken cancellationToken);

    /// <summary>Tutti i film di Radarr, con id, durata e file (spec T §2).</summary>
    Task<IReadOnlyList<RadarrMovie?>> GetLibraryMoviesAsync(CancellationToken cancellationToken);

    /// <summary>Gli episodi mancanti e monitorati di Sonarr, con la serie; tutte le pagine (spec T §2).</summary>
    Task<IReadOnlyList<SonarrEpisode?>> GetMissingEpisodesAsync(CancellationToken cancellationToken);

    /// <summary>I file dei film con questi id di file, a gruppi di 100 (spec T §2).</summary>
    Task<IReadOnlyList<ArrFile?>> GetMovieFilesAsync(IReadOnlyList<int> movieFileIds, CancellationToken cancellationToken);

    /// <summary>I file degli episodi di una serie di Sonarr (spec T §2).</summary>
    Task<IReadOnlyList<ArrFile?>> GetEpisodeFilesAsync(int seriesId, CancellationToken cancellationToken);

    /// <summary>I profili di qualità (spec T §2).</summary>
    Task<IReadOnlyList<ArrQualityProfile?>> GetQualityProfilesAsync(ArrKind kind, CancellationToken cancellationToken);

    /// <summary>La coda dei download; tutte le pagine (spec T §2).</summary>
    Task<IReadOnlyList<ArrQueueItem?>> GetQueueAsync(ArrKind kind, CancellationToken cancellationToken);

    /// <summary>Toglie una voce dalla coda e dal client di download, con o senza blocklist (spec T §2).</summary>
    Task RemoveFromQueueAsync(ArrKind kind, int queueId, bool blocklist, CancellationToken cancellationToken);

    /// <summary>Gli indexer, con la priorità (numero più basso = preferito) (spec T §2).</summary>
    Task<IReadOnlyList<ArrIndexer?>> GetIndexersAsync(ArrKind kind, CancellationToken cancellationToken);
}
