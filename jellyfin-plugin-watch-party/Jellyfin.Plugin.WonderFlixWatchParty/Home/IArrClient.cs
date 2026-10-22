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

    Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken);
}
