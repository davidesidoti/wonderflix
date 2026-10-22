namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una serie di Jellyfin con i suoi id esterni (null quelli che non ha).</summary>
public sealed record LibrarySeries(Guid Id, string? TvdbId, string? TmdbId, string? ImdbId);

/// <summary>Un film di Jellyfin con il suo id TMDB (null se non ce l'ha), spec S §6.1.</summary>
public sealed record LibraryMovie(Guid Id, string? TmdbId);

/// <summary>Le serie della libreria, per riconoscere quelle di Sonarr (adattatore di ILibraryManager).</summary>
public interface ISeriesIndex
{
    /// <summary>Tutte le serie, di tutte le librerie, senza guardare l'utente.</summary>
    IReadOnlyList<LibrarySeries> GetSeries();

    /// <summary>Tutti i film, di tutte le librerie, senza guardare l'utente.</summary>
    IReadOnlyList<LibraryMovie> GetMovies();
}
