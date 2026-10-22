using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Le date di uscita delle richieste (spec S §6.2): film per id TMDB, serie dalla
/// libreria di Sonarr. Ogni lettura passa da una cache a chiavi; non lancia mai,
/// tranne l'annullamento di chi chiama. Senza date il risultato è null.
/// </summary>
public sealed class ReleaseDatesService(
    IArrClient client,
    IArrSettings settings,
    TimeProvider time,
    ILogger<ReleaseDatesService> logger)
{
    /// <summary>Film tenuti in cache.</summary>
    public const int MaxCachedMovies = 500;

    /// <summary>Elenchi di episodi (uno per serie) tenuti in cache.</summary>
    public const int MaxCachedSeriesEpisodes = 200;

    private readonly ArrReadCache<MovieDates?> _movies = new(time, MaxCachedMovies, logger);
    private readonly ArrReadCache<IReadOnlyList<SonarrSeries?>> _library = new(time, 1, logger);
    private readonly ArrReadCache<IReadOnlyList<SonarrEpisode?>> _episodes = new(time, MaxCachedSeriesEpisodes, logger);

    /// <summary>Le date del film; null se Radarr non è configurato, non risponde o non lo conosce.</summary>
    public async Task<MovieDates?> GetMovieAsync(int tmdbId, CancellationToken cancellationToken)
    {
        var radarr = settings.Radarr;
        if (!radarr.IsConfigured || tmdbId <= 0)
        {
            return null;
        }

        try
        {
            var read = await _movies.GetAsync($"{radarr.Url}\n{radarr.ApiKey}\n{tmdbId}", () => ReadMovieAsync(tmdbId))
                .WaitAsync(cancellationToken).ConfigureAwait(false);
            return read.Value;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Date di uscita: film {TmdbId} non letto", tmdbId);
            return null;
        }
    }

    /// <summary>Il prossimo episodio della serie (per TVDB, poi TMDB); null senza serie o senza <c>NextAiring</c>.</summary>
    public async Task<SeriesNext?> GetSeriesAsync(int? tvdbId, int tmdbId, CancellationToken cancellationToken)
    {
        var sonarr = settings.Sonarr;
        if (!sonarr.IsConfigured)
        {
            return null;
        }

        try
        {
            var prefix = $"{sonarr.Url}\n{sonarr.ApiKey}\n";
            var library = (await _library.GetAsync(prefix, () => client.GetSeriesAsync(CancellationToken.None))
                .WaitAsync(cancellationToken).ConfigureAwait(false)).Value ?? [];
            var series = (tvdbId > 0 ? library.FirstOrDefault(s => s is not null && s.TvdbId == tvdbId) : null)
                ?? (tmdbId > 0 ? library.FirstOrDefault(s => s is not null && s.TmdbId == tmdbId) : null);
            if (series?.NextAiring is not { } nextAiring)
            {
                return null;
            }

            var episodes = (await _episodes.GetAsync(
                    $"{prefix}{series.Id}", () => client.GetSeriesEpisodesAsync(series.Id, CancellationToken.None))
                .WaitAsync(cancellationToken).ConfigureAwait(false)).Value ?? [];
            var episode = episodes
                .Where(e => e is not null && e.AirDateUtc == nextAiring)
                .OrderBy(e => e!.SeasonNumber > 0 ? 0 : 1)
                .ThenBy(e => e!.SeasonNumber)
                .ThenBy(e => e!.EpisodeNumber)
                .FirstOrDefault();
            return new SeriesNext(nextAiring, episode?.SeasonNumber, episode?.EpisodeNumber);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Date di uscita: serie {TvdbId}/{TmdbId} non letta", tvdbId, tmdbId);
            return null;
        }
    }

    private async Task<MovieDates?> ReadMovieAsync(int tmdbId)
    {
        var found = (await client.FindMoviesAsync(tmdbId, CancellationToken.None).ConfigureAwait(false))
            .FirstOrDefault(m => m is not null);
        if (found is not null)
        {
            return new MovieDates(found.InCinemas, found.DigitalRelease, found.PhysicalRelease, found.HasFile);
        }

        var lookup = await client.LookupMovieAsync(tmdbId, CancellationToken.None).ConfigureAwait(false);
        return new MovieDates(lookup.InCinemas, lookup.DigitalRelease, lookup.PhysicalRelease, false);
    }
}
