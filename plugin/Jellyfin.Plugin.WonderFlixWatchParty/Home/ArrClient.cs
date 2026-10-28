using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// HTTP verso Sonarr e Radarr (API v3), con X-Api-Key su ogni chiamata.
/// Nel registro vanno solo servizio, percorso ed esito: mai la chiave, mai la query.
/// </summary>
public sealed class ArrClient(
    IHttpClientFactory httpClientFactory,
    IArrSettings settings,
    ILogger<ArrClient> logger) : IArrClient
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixArr";

    /// <summary>Attesa massima di una risposta (spec M §7.4).</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Attesa massima di una ricerca dal vivo: gli indexer rispondono piano (spec T §2).</summary>
    public static readonly TimeSpan SearchTimeout = TimeSpan.FromMinutes(2);

    /// <summary>Record per pagina di <c>queue</c> e <c>wanted/missing</c> (spec T §2).</summary>
    private const int PageSize = 250;

    /// <summary>Id di file per chiamata a <c>moviefile</c>: l'indirizzo non deve diventare troppo lungo (spec T §2).</summary>
    private const int MovieFileGroup = 100;

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public async Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken) =>
        await GetAsync<List<SonarrEpisode?>>(
            ArrKind.Sonarr,
            $"calendar?start={Iso(from)}&end={Iso(to)}&includeSeries=true&unmonitored=false",
            cancellationToken).ConfigureAwait(false);

    public async Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken) =>
        await GetAsync<List<RadarrMovie?>>(
            ArrKind.Radarr,
            $"calendar?start={Iso(from)}&end={Iso(to)}&unmonitored=false",
            cancellationToken).ConfigureAwait(false);

    public async Task<IReadOnlyList<RadarrMovie?>> FindMoviesAsync(int tmdbId, CancellationToken cancellationToken) =>
        await GetAsync<List<RadarrMovie?>>(
            ArrKind.Radarr, $"movie?tmdbId={tmdbId.ToString(CultureInfo.InvariantCulture)}", cancellationToken)
            .ConfigureAwait(false);

    public Task<RadarrMovie> LookupMovieAsync(int tmdbId, CancellationToken cancellationToken) =>
        GetAsync<RadarrMovie>(
            ArrKind.Radarr, $"movie/lookup/tmdb?tmdbId={tmdbId.ToString(CultureInfo.InvariantCulture)}", cancellationToken);

    public async Task<IReadOnlyList<SonarrSeries?>> GetSeriesAsync(CancellationToken cancellationToken) =>
        await GetAsync<List<SonarrSeries?>>(ArrKind.Sonarr, "series", cancellationToken).ConfigureAwait(false);

    public async Task<IReadOnlyList<SonarrEpisode?>> GetSeriesEpisodesAsync(int seriesId, CancellationToken cancellationToken) =>
        await GetAsync<List<SonarrEpisode?>>(
            ArrKind.Sonarr, $"episode?seriesId={seriesId.ToString(CultureInfo.InvariantCulture)}", cancellationToken)
            .ConfigureAwait(false);

    public Task<SonarrEpisode> GetEpisodeAsync(int episodeId, CancellationToken cancellationToken) =>
        GetAsync<SonarrEpisode>(ArrKind.Sonarr, $"episode/{episodeId.ToString(CultureInfo.InvariantCulture)}", cancellationToken);

    public Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken) =>
        GetAsync<ArrStatus>(kind, "system/status", cancellationToken);

    public async Task<IReadOnlyList<ArrRelease?>> SearchReleasesAsync(
        ArrKind kind, string query, CancellationToken cancellationToken) =>
        await SendAsync<List<ArrRelease?>>(kind, HttpMethod.Get, $"release?{query}", null, SearchTimeout, cancellationToken)
            .ConfigureAwait(false);

    public Task GrabReleaseAsync(ArrKind kind, string guid, int indexerId, CancellationToken cancellationToken) =>
        SendWithoutResultAsync(kind, HttpMethod.Post, "release", new { guid, indexerId }, cancellationToken);

    public async Task<IReadOnlyList<RadarrMovie?>> GetLibraryMoviesAsync(CancellationToken cancellationToken) =>
        await GetAsync<List<RadarrMovie?>>(ArrKind.Radarr, "movie", cancellationToken).ConfigureAwait(false);

    public Task<IReadOnlyList<SonarrEpisode?>> GetMissingEpisodesAsync(CancellationToken cancellationToken) =>
        GetAllPagesAsync<SonarrEpisode>(
            ArrKind.Sonarr,
            page => $"wanted/missing?page={page.ToString(CultureInfo.InvariantCulture)}&pageSize={PageSize}"
                + "&monitored=true&includeSeries=true",
            cancellationToken);

    public async Task<IReadOnlyList<ArrFile?>> GetMovieFilesAsync(
        IReadOnlyList<int> movieFileIds, CancellationToken cancellationToken)
    {
        var files = new List<ArrFile?>();
        foreach (var group in movieFileIds.Chunk(MovieFileGroup))
        {
            var query = string.Join(
                "&", group.Select(id => "movieFileIds=" + id.ToString(CultureInfo.InvariantCulture)));
            files.AddRange(
                await GetAsync<List<ArrFile?>>(ArrKind.Radarr, $"moviefile?{query}", cancellationToken).ConfigureAwait(false));
        }

        return files;
    }

    public async Task<IReadOnlyList<ArrFile?>> GetEpisodeFilesAsync(int seriesId, CancellationToken cancellationToken) =>
        await GetAsync<List<ArrFile?>>(
            ArrKind.Sonarr, $"episodefile?seriesId={seriesId.ToString(CultureInfo.InvariantCulture)}", cancellationToken)
            .ConfigureAwait(false);

    public async Task<IReadOnlyList<ArrQualityProfile?>> GetQualityProfilesAsync(
        ArrKind kind, CancellationToken cancellationToken) =>
        await GetAsync<List<ArrQualityProfile?>>(kind, "qualityprofile", cancellationToken).ConfigureAwait(false);

    public Task<IReadOnlyList<ArrQueueItem?>> GetQueueAsync(ArrKind kind, CancellationToken cancellationToken) =>
        GetAllPagesAsync<ArrQueueItem>(
            kind, page => $"queue?page={page.ToString(CultureInfo.InvariantCulture)}&pageSize={PageSize}", cancellationToken);

    public Task RemoveFromQueueAsync(ArrKind kind, int queueId, bool blocklist, CancellationToken cancellationToken) =>
        SendWithoutResultAsync(
            kind,
            HttpMethod.Delete,
            $"queue/{queueId.ToString(CultureInfo.InvariantCulture)}?removeFromClient=true&blocklist={(blocklist ? "true" : "false")}",
            null,
            cancellationToken);

    public async Task<IReadOnlyList<ArrIndexer?>> GetIndexersAsync(ArrKind kind, CancellationToken cancellationToken) =>
        await GetAsync<List<ArrIndexer?>>(kind, "indexer", cancellationToken).ConfigureAwait(false);

    /// <summary>Data e ora UTC in ISO 8601, come le vuole il calendario, pronte per la query.</summary>
    internal static string Iso(DateTimeOffset value) =>
        Uri.EscapeDataString(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));

    /// <summary>401 e 403: chiave rifiutata; ogni altra risposta non riuscita: irraggiungibile.</summary>
    internal static ArrError Classify(int status) => status is 401 or 403 ? ArrError.Unauthorized : ArrError.Unreachable;

    private Task<T> GetAsync<T>(ArrKind kind, string path, CancellationToken cancellationToken) =>
        SendAsync<T>(kind, HttpMethod.Get, path, null, Timeout, cancellationToken);

    private Task<T> SendAsync<T>(
        ArrKind kind, HttpMethod method, string path, object? body, TimeSpan timeout, CancellationToken cancellationToken) =>
        SendCoreAsync(
            kind,
            method,
            path,
            body,
            timeout,
            async (response, token) =>
                await response.Content.ReadFromJsonAsync<T>(ArrJson.Options, token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota"),
            cancellationToken);

    /// <summary>Una chiamata di cui conta solo l'esito: il corpo della risposta non si legge.</summary>
    private Task SendWithoutResultAsync(
        ArrKind kind, HttpMethod method, string path, object? body, CancellationToken cancellationToken) =>
        SendCoreAsync(kind, method, path, body, Timeout, (_, _) => Task.FromResult(true), cancellationToken);

    /// <summary>Tutte le pagine di <c>queue</c> o <c>wanted/missing</c>: si ferma al totale o a una pagina vuota.</summary>
    private async Task<IReadOnlyList<T?>> GetAllPagesAsync<T>(
        ArrKind kind, Func<int, string> pagePath, CancellationToken cancellationToken)
    {
        var all = new List<T?>();
        for (var page = 1; ; page++)
        {
            var result = await GetAsync<ArrPage<T>>(kind, pagePath(page), cancellationToken).ConfigureAwait(false);
            var records = result.Records ?? [];
            all.AddRange(records);
            if (records.Count == 0 || all.Count >= result.TotalRecords)
            {
                return all;
            }
        }
    }

    private async Task<T> SendCoreAsync<T>(
        ArrKind kind,
        HttpMethod method,
        string path,
        object? body,
        TimeSpan timeout,
        Func<HttpResponseMessage, CancellationToken, Task<T>> read,
        CancellationToken cancellationToken)
    {
        var endpoint = settings.Endpoint(kind);
        if (!endpoint.IsConfigured)
        {
            throw new ArrException(ArrError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        try
        {
            using var request = new HttpRequestMessage(method, $"{endpoint.Url}/api/v3/{path}");
            request.Headers.Add("X-Api-Key", endpoint.ApiKey);
            if (body is not null)
            {
                request.Content = JsonContent.Create(body, options: ArrJson.Options);
            }

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeoutSource.Token)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogInformation("{Service} {Method} {Path}: {Status}", kind, method, logPath, (int)response.StatusCode);
                throw new ArrException(Classify((int)response.StatusCode), null, (int)response.StatusCode);
            }

            return await read(response, timeoutSource.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("{Service} {Method} {Path}: nessuna risposta in {Timeout}", kind, method, logPath, timeout);
            throw new ArrException(ArrError.Unreachable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or FormatException)
        {
            // FormatException copre UriFormatException e Headers.Add con una chiave con a capo.
            // Questi messaggi non contengono né la chiave né la query.
            logger.LogWarning(
                "{Service} {Method} {Path} non riuscita: {Error} {Message}", kind, method, logPath, ex.GetType().Name, ex.Message);
            throw new ArrException(ArrError.Unreachable, ex);
        }
    }
}
