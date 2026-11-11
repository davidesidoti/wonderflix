using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// La ricerca di sempre per l'<see cref="SearchEngine.Arr"/>, e per Prowlarr: query per titolo, parse con Sonarr/Radarr.
/// Senza <paramref name="prowlarr"/> usa sempre la strada <see cref="SearchEngine.Arr"/>.
/// </summary>
public sealed class ReleaseFinder(IArrClient arr, IProwlarrClient? prowlarr, IArrSettings settings, ILogger<ReleaseFinder> logger, IQbitClient? qbit, TimeProvider time) : IReleaseFinder
{
    // Il parse non mette niente in cache e un parallelismo piccolo basta (1640 release in 6 s in sequenza).
    private const int ParseParallelism = 4;

    // I rifiuti del push per file, coda o monitoraggio: per un download voluto non contano.
    private static readonly string[] IntentionalRejections =
    [
        "Existing file on disk",
        "Not an upgrade",
        "Release in queue",
        "Series is not monitored",
        "Episode is not monitored",
        "One or more episodes is not monitored",
        "Movie is not monitored",
        "Not a Custom Format upgrade",
        "Existing file meets cutoff",
    ];

    // Il push dice "approvata" anche quando il client la rifiuta: si cerca il grab nella cronologia per così tanto.
    internal static readonly TimeSpan ConfirmWindow = TimeSpan.FromSeconds(15);

    private static readonly TimeSpan ConfirmPoll = TimeSpan.FromSeconds(1);

    // Il margine sull'ora del push per la cronologia: gli orologi di plugin e Sonarr/Radarr possono differire un po'.
    private static readonly TimeSpan ConfirmMargin = TimeSpan.FromSeconds(10);

    // Un grab riconosciuto solo dal titolo (serie/film) vale se è di poco prima del push o dopo.
    private static readonly TimeSpan FallbackMargin = TimeSpan.FromSeconds(5);

    /// <summary>L'attesa fra due letture della cronologia; i test la sostituiscono per non aspettare davvero.</summary>
    internal Func<TimeSpan, CancellationToken, Task> Wait { get; init; } = (delay, token) => Task.Delay(delay, time, token);

    public bool UsesProwlarr => prowlarr is not null && settings.Prowlarr.IsConfigured;

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

    public async Task<GrabResult> GrabAsync(ArrKind service, ArrRelease release, bool intentional, CancellationToken cancellationToken)
    {
        if (release.Source != ReleaseSource.Prowlarr)
        {
            await arr.GrabReleaseAsync(service, release.Guid ?? string.Empty, release.IndexerId, cancellationToken).ConfigureAwait(false);
            return new GrabResult(GrabKind.Grabbed, null, null);
        }

        ArrPushResult decision;
        var pushedAt = time.GetUtcNow();
        try
        {
            decision = await arr.PushReleaseAsync(
                service,
                new ArrPushRelease
                {
                    Title = release.Title ?? string.Empty,
                    DownloadUrl = release.DownloadUrl,
                    MagnetUrl = release.MagnetUrl,
                    Protocol = release.Protocol ?? "torrent",
                    PublishDate = release.PublishDate ?? time.GetUtcNow(),
                    Size = release.Size,
                    IndexerId = release.IndexerId,
                    Seeders = release.Seeders,
                },
                cancellationToken).ConfigureAwait(false);
        }
        catch (ArrException ex) when (ex.Status == 400)
        {
            // "Unable to parse": Sonarr/Radarr non sanno a cosa attribuirla, è un rifiuto di regola. Nel log lo stato, così un
            // errore di validazione del push si vede (mai titolo né chiavi).
            logger.LogWarning("Push rifiutato da {Kind} con stato {Status}: release scartata per regola", service, ex.Status);
            return new GrabResult(GrabKind.RuleRefused, "Unable to parse", null);
        }

        if (decision.Approved)
        {
            return await ConfirmGrabAsync(service, release, pushedAt, cancellationToken).ConfigureAwait(false)
                ? new GrabResult(GrabKind.Grabbed, null, null)
                : new GrabResult(GrabKind.ClientRefused, null, null);
        }

        if (decision.TemporarilyRejected)
        {
            return new GrabResult(GrabKind.Pending, null, null);
        }

        var reasons = decision.Rejections?.Where(r => !string.IsNullOrWhiteSpace(r)).ToList() ?? [];
        if (!intentional || reasons.Count == 0
            || !reasons.All(r => IntentionalRejections.Any(p => r.StartsWith(p, StringComparison.OrdinalIgnoreCase))))
        {
            return new GrabResult(GrabKind.RuleRefused, reasons.FirstOrDefault(), null);
        }

        var hash = await AddDirectAsync(service, release, cancellationToken).ConfigureAwait(false);

        // Mai il titolo nel log (è quello che l'utente cerca); i motivi sono di Sonarr/Radarr.
        logger.LogInformation("Push rifiutato ({Reason}): torrent aggiunto direttamente a qBittorrent", reasons[0]);
        return new GrabResult(GrabKind.Direct, null, hash);
    }

    // Sonarr/Radarr rispondono "approvata" anche se il client di download la rifiuta (l'errore resta dentro di loro): il grab
    // è vero solo se compare nella cronologia. Una cronologia che non risponde non dice niente: il grab resta.
    private async Task<bool> ConfirmGrabAsync(ArrKind service, ArrRelease release, DateTimeOffset pushedAt, CancellationToken cancellationToken)
    {
        // La finestra parte dalla risposta del push: un push lento non deve consumarla.
        var deadline = time.GetUtcNow() + ConfirmWindow;
        while (true)
        {
            try
            {
                var grabs = await arr.GetGrabHistoryAsync(service, pushedAt - ConfirmMargin, cancellationToken).ConfigureAwait(false);
                if (grabs.OfType<ArrHistoryRecord>().Any(g => IsGrabOf(g, service, release, pushedAt)))
                {
                    return true;
                }
            }
            catch (ArrException ex)
            {
                logger.LogWarning("Cronologia di {Kind} non letta ({Error}): il push approvato vale come preso", service, ex.Error);
                return true;
            }

            if (time.GetUtcNow() >= deadline)
            {
                logger.LogWarning("Push approvato da {Kind} ma nessun grab nella cronologia: rifiutato dal client", service);
                return false;
            }

            await Wait(ConfirmPoll, cancellationToken).ConfigureAwait(false);
        }
    }

    // Il titolo nella cronologia è normalizzato da Sonarr/Radarr ("[CB46E567].mkv" → "[CB46E567] mkv", accenti tolti): non si
    // confronta. Conta il link spinto (guid "PUSH-" + link, o downloadUrl), l'hash del magnet, se no un grab dello stesso titolo
    // (serie, episodio o film) da poco prima del push.
    private static bool IsGrabOf(ArrHistoryRecord grab, ArrKind service, ArrRelease release, DateTimeOffset pushedAt)
    {
        var link = release.DownloadUrl ?? release.MagnetUrl;
        var data = grab.Data ?? [];
        if (link is not null
            && (data.GetValueOrDefault("guid") == "PUSH-" + link || data.GetValueOrDefault("downloadUrl") == link))
        {
            return true;
        }

        if (release.MagnetUrl is { } magnet && QbitClient.HashOfMagnet(magnet) is { } hash
            && (string.Equals(grab.DownloadId, hash, StringComparison.OrdinalIgnoreCase)
                || string.Equals(data.GetValueOrDefault("torrentInfoHash"), hash, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        if (grab.Date is not { } date || date < pushedAt - FallbackMargin || release.TitleId <= 0)
        {
            return false;
        }

        return service == ArrKind.Radarr
            ? grab.MovieId == release.TitleId
            : grab.SeriesId == release.TitleId || (release.EpisodeId is { } episode && grab.EpisodeId == episode);
    }

    public async Task<string> AddDirectAsync(ArrKind service, ArrRelease release, CancellationToken cancellationToken)
    {
        // La categoria del client di Sonarr/Radarr: così il torrent finisce dove finiscono i loro.
        var category = (await arr.GetDownloadClientsAsync(service, cancellationToken).ConfigureAwait(false))
            .OfType<ArrDownloadClient>()
            .Where(c => c.Enable && string.Equals(c.Implementation, "QBittorrent", StringComparison.OrdinalIgnoreCase))
            .Select(c => c.Category)
            .FirstOrDefault(c => !string.IsNullOrEmpty(c))
            ?? throw new QbitException(QbitError.NotConfigured);
        var link = release.MagnetUrl ?? release.DownloadUrl ?? throw new QbitException(QbitError.NotFound);
        return await (qbit ?? throw new QbitException(QbitError.NotConfigured)).AddAsync(link, category, cancellationToken).ConfigureAwait(false);
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
                    foreach (var release in await prowlarr!.SearchAsync(new ProwlarrQuery(type, query, season, episode, ids, categories), cancellationToken).ConfigureAwait(false))
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
