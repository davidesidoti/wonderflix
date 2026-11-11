using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>La ricerca di sempre per l'<see cref="SearchEngine.Arr"/>, e per Prowlarr: query per titolo, parse con Sonarr/Radarr.</summary>
public sealed class ReleaseFinder(IArrClient arr, IProwlarrClient prowlarr, IArrSettings settings, ILogger<ReleaseFinder> logger) : IReleaseFinder
{
    // Il parse non mette niente in cache e un parallelismo piccolo basta (1640 release in 6 s in sequenza).
    private const int ParseParallelism = 4;

    public bool UsesProwlarr => settings.Prowlarr.IsConfigured;

    /// <summary>La query di <c>release</c> di Sonarr/Radarr per la chiave.</summary>
    internal static string QueryOf(DownloadKey key) => key.Kind switch
    {
        DownloadKinds.Movie => string.Create(CultureInfo.InvariantCulture, $"movieId={key.Id}"),
        DownloadKinds.Episode => string.Create(CultureInfo.InvariantCulture, $"episodeId={key.Id}"),
        _ => string.Create(CultureInfo.InvariantCulture, $"seriesId={key.Id}&seasonNumber={key.Season}"),
    };

    internal static ArrKind ServiceOf(string kind) => kind == DownloadKinds.Movie ? ArrKind.Radarr : ArrKind.Sonarr;

    public async Task<FinderResult> SearchAsync(DownloadKey key, SearchEngine engine, CancellationToken cancellationToken, TimeSpan? arrTimeout = null)
    {
        var service = ServiceOf(key.Kind);
        if (engine == SearchEngine.Arr || !UsesProwlarr)
        {
            var found = await arr.SearchReleasesAsync(service, QueryOf(key), cancellationToken, arrTimeout).ConfigureAwait(false);
            return new FinderResult(found, [], SearchEngine.Arr);
        }

        return await SearchProwlarrAsync(key, service, cancellationToken).ConfigureAwait(false);
    }

    private async Task<FinderResult> SearchProwlarrAsync(DownloadKey key, ArrKind service, CancellationToken cancellationToken)
    {
        var (queries, anime) = await QueriesAsync(key, cancellationToken).ConfigureAwait(false);

        // Solo gli indexer del servizio che vengono da Prowlarr e cercano a mano; per ogni id di Prowlarr quello del servizio.
        var indexers = (await arr.GetIndexersAsync(service, cancellationToken).ConfigureAwait(false))
            .OfType<ArrIndexer>()
            .Where(i => i.EnableInteractiveSearch && i.ProwlarrId is not null)
            .GroupBy(i => i.ProwlarrId!.Value)
            .ToDictionary(g => g.Key, g => g.First());

        // Gli indexer con le stesse categorie viaggiano nella stessa richiesta.
        var groups = indexers.Values
            .GroupBy(i => string.Join(',', CategoriesOf(i, anime)))
            .Select(g => (Ids: (IReadOnlyList<int>)[.. g.Select(i => i.ProwlarrId!.Value)], Categories: CategoriesOf(g.First(), anime)))
            .ToList();

        // Una richiesta alla volta; deduplica per indexer e guid.
        var unique = new Dictionary<string, ProwlarrRelease>();
        var (calls, failures) = (0, 0);
        ArrException? lastError = null;
        foreach (var (type, query, season, episode) in queries)
        {
            foreach (var (ids, categories) in groups)
            {
                calls++;
                try
                {
                    foreach (var release in await prowlarr.SearchAsync(new ProwlarrQuery(type, query, season, episode, ids, categories), cancellationToken).ConfigureAwait(false))
                    {
                        // Un indexer che il servizio non conosce non si potrebbe scaricare.
                        if (indexers.ContainsKey(release.IndexerId))
                        {
                            unique.TryAdd($"{release.IndexerId}|{release.Guid}", release);
                        }
                    }
                }
                catch (ArrException ex)
                {
                    (failures, lastError) = (failures + 1, ex);

                    // Mai la query nel log: è il titolo che l'utente cerca.
                    logger.LogWarning("Ricerca su Prowlarr non riuscita ({Error}): query saltata", ex.Error);
                }
            }
        }

        // Una query che fallisce si salta; se falliscono tutte la ricerca è fallita.
        if (calls > 0 && failures == calls)
        {
            throw lastError!;
        }

        var found = unique.Values.ToList();
        var parsed = new ArrRelease?[found.Count];
        var (parseFailures, parseError) = (0, (ArrException?)null);
        await Parallel.ForEachAsync(
            Enumerable.Range(0, found.Count),
            new ParallelOptions { MaxDegreeOfParallelism = ParseParallelism, CancellationToken = cancellationToken },
            async (i, token) =>
            {
                try
                {
                    var parse = await arr.ParseAsync(service, found[i].Title ?? string.Empty, token).ConfigureAwait(false);
                    parsed[i] = ParsedRelease.From(found[i], parse, indexers[found[i].IndexerId].Id, key);
                }
                catch (ArrException ex)
                {
                    // Una release che non si legge si scarta; mai il titolo nel log.
                    Interlocked.Increment(ref parseFailures);
                    parseError = ex;
                }
            }).ConfigureAwait(false);

        if (parseFailures > 0)
        {
            logger.LogWarning("Parse di Sonarr/Radarr non riuscito per {Failed} release su {Total}: scartate", parseFailures, found.Count);

            // Se non se ne legge nessuna il servizio non risponde: la ricerca è fallita.
            if (parseFailures == found.Count)
            {
                throw parseError!;
            }
        }

        return new FinderResult(
            [.. parsed.OfType<ArrRelease>().Where(r => r.WrongTitle is null)],
            [.. parsed.OfType<ArrRelease>().Where(r => r.WrongTitle is not null)],
            SearchEngine.Prowlarr);
    }

    // Le query per titolo, e se la serie è un anime (per le categorie degli indexer).
    private async Task<(IReadOnlyList<(string Type, string Query, int? Season, int? Episode)> Queries, bool Anime)> QueriesAsync(DownloadKey key, CancellationToken cancellationToken)
    {
        if (key.Kind == DownloadKinds.Movie)
        {
            var movie = await arr.GetMovieAsync(key.Id, cancellationToken).ConfigureAwait(false);
            return (ReleaseQueries.ForMovie(movie), false);
        }

        if (key.Kind == DownloadKinds.Episode)
        {
            // La serie dell'episodio ha i titoli alternativi e il tipo, l'episodio no.
            var episode = await arr.GetEpisodeAsync(key.Id, cancellationToken).ConfigureAwait(false);
            var episodeSeries = await arr.GetSeriesByIdAsync(episode.SeriesId, cancellationToken).ConfigureAwait(false);
            return (ReleaseQueries.ForEpisode(episodeSeries, episode), episodeSeries.SeriesType == "anime");
        }

        var series = await arr.GetSeriesByIdAsync(key.Id, cancellationToken).ConfigureAwait(false);
        return (ReleaseQueries.ForSeason(series, key.Season), series.SeriesType == "anime");
    }

    private static IReadOnlyList<int> CategoriesOf(ArrIndexer indexer, bool anime) =>
        anime && indexer.AnimeCategories.Count > 0 ? indexer.AnimeCategories : indexer.Categories;
}
