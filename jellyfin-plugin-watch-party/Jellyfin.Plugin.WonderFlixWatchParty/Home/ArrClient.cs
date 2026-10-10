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

    public Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken) =>
        GetAsync<ArrStatus>(kind, "system/status", cancellationToken);

    /// <summary>Data e ora UTC in ISO 8601, come le vuole il calendario, pronte per la query.</summary>
    internal static string Iso(DateTimeOffset value) =>
        Uri.EscapeDataString(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));

    /// <summary>401 e 403: chiave rifiutata; ogni altra risposta non riuscita: irraggiungibile.</summary>
    internal static ArrError Classify(int status) => status is 401 or 403 ? ArrError.Unauthorized : ArrError.Unreachable;

    private async Task<T> GetAsync<T>(ArrKind kind, string path, CancellationToken cancellationToken)
    {
        var endpoint = settings.Endpoint(kind);
        if (!endpoint.IsConfigured)
        {
            throw new ArrException(ArrError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{endpoint.Url}/api/v3/{path}");
            request.Headers.Add("X-Api-Key", endpoint.ApiKey);
            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeout.Token)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogInformation("{Service} GET {Path}: {Status}", kind, logPath, (int)response.StatusCode);
                throw new ArrException(Classify((int)response.StatusCode));
            }

            return await response.Content.ReadFromJsonAsync<T>(ArrJson.Options, timeout.Token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("{Service} GET {Path}: nessuna risposta in {Timeout}", kind, logPath, Timeout);
            throw new ArrException(ArrError.Unreachable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or FormatException)
        {
            // FormatException copre UriFormatException e Headers.Add con una chiave con a capo.
            // Questi messaggi non contengono né la chiave né la query.
            logger.LogWarning(
                "{Service} GET {Path} non riuscita: {Error} {Message}", kind, logPath, ex.GetType().Name, ex.Message);
            throw new ArrException(ArrError.Unreachable, ex);
        }
    }
}
