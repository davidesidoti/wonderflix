using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// HTTP verso Seerr (spec I §7.2): X-API-Key su ogni chiamata, X-API-User
/// su quelle fatte per conto di un utente. Nel registro vanno solo metodo,
/// percorso ed esito: mai la chiave, mai la query.
/// </summary>
public sealed class SeerrClient(
    IHttpClientFactory httpClientFactory,
    ISeerrSettings settings,
    ILogger<SeerrClient> logger) : ISeerrClient
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixSeerr";

    /// <summary>Utenti letti in una volta (sul server sono 28).</summary>
    public const int MaxUsers = 1000;

    /// <summary>Attesa massima di una risposta di Seerr (spec I §7.2).</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrStatusInfo>(HttpMethod.Get, "status", null, null, cancellationToken);

    public Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrUser>(HttpMethod.Get, "auth/me", null, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken) =>
        (await SendAsync<SeerrPage<SeerrUser>>(
            HttpMethod.Get, $"user?take={MaxUsers}&skip=0", null, null, cancellationToken).ConfigureAwait(false)).Results;

    public Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken) =>
        SendAsync<JsonElement>(
            HttpMethod.Post,
            "user/import-from-jellyfin",
            null,
            new SeerrImportUsers { JellyfinUserIds = [jellyfinUserId.ToString("N")] },
            cancellationToken);

    public Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrMainSettings>(HttpMethod.Get, "settings/main", null, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(
        string query, string language, CancellationToken cancellationToken) =>
        (await SendAsync<SeerrSearchPage>(
            HttpMethod.Get,
            $"search?query={Uri.EscapeDataString(query)}&page=1&language={Uri.EscapeDataString(language)}",
            null,
            null,
            cancellationToken).ConfigureAwait(false)).Results;

    public Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken) =>
        SendAsync<SeerrMovie>(
            HttpMethod.Get, $"movie/{tmdbId}?language={Uri.EscapeDataString(language)}", null, null, cancellationToken);

    public Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken) =>
        SendAsync<SeerrTv>(
            HttpMethod.Get, $"tv/{tmdbId}?language={Uri.EscapeDataString(language)}", null, null, cancellationToken);

    public Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(
            HttpMethod.Post, "request", asUser, body, cancellationToken, acceptedMeans: SeerrError.NothingToRequest);

    public Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken)
    {
        var path = $"request?take={take}&skip={skip}&filter={Uri.EscapeDataString(filter)}&sort=added&sortDirection=desc";
        if (requestedBy is { } user)
        {
            path += $"&requestedBy={user}";
        }

        return SendAsync<SeerrPage<SeerrRequest>>(HttpMethod.Get, path, asUser, null, cancellationToken);
    }

    public Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(HttpMethod.Get, $"request/{requestId}", asUser, null, cancellationToken);

    public Task UpdateRequestAsync(
        int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken) =>
        SendAsync<JsonElement>(
            HttpMethod.Put, $"request/{requestId}", asUser, body, cancellationToken,
            acceptedMeans: SeerrError.NothingToRequest);

    public Task<SeerrRequest> SetRequestStatusAsync(
        int asUser, int requestId, bool approve, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(
            HttpMethod.Post, $"request/{requestId}/{(approve ? "approve" : "decline")}", asUser, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken) =>
        await SendAsync<List<SeerrServer>>(HttpMethod.Get, $"service/{service}", null, null, cancellationToken)
            .ConfigureAwait(false);

    public Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken) =>
        SendAsync<SeerrServerDetails>(HttpMethod.Get, $"service/{service}/{serverId}", null, null, cancellationToken);

    /// <summary>
    /// Da stato e messaggio di Seerr all'errore. Una chiamata senza
    /// X-API-User agisce come l'utente 1 (admin): lì un 403 vuol dire chiave
    /// rifiutata, perché Seerr risponde 403 (non 401) senza utente.
    /// </summary>
    internal static SeerrError Classify(int status, string message, bool asAdmin) => status switch
    {
        401 => SeerrError.Auth,
        403 when asAdmin => SeerrError.Auth,
        403 when message.Contains("quota", StringComparison.OrdinalIgnoreCase) => SeerrError.QuotaExceeded,
        403 when message.Contains("blocklist", StringComparison.OrdinalIgnoreCase) => SeerrError.Blocklisted,
        403 => SeerrError.NoPermission,
        404 => SeerrError.NotFound,
        409 => SeerrError.AlreadyRequested,
        400 => SeerrError.BadRequest,
        _ => SeerrError.Unavailable,
    };

    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        int? asUser,
        object? body,
        CancellationToken cancellationToken,
        SeerrError? acceptedMeans = null)
    {
        var baseUrl = settings.Url;
        var key = settings.ApiKey;
        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(key))
        {
            throw new SeerrException(SeerrError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = new HttpRequestMessage(method, $"{baseUrl}/api/v1/{path}");
            request.Headers.Add("X-API-Key", key);
            if (asUser is { } user)
            {
                request.Headers.Add("X-API-User", user.ToString(CultureInfo.InvariantCulture));
            }

            if (body is not null)
            {
                request.Content = JsonContent.Create(body, body.GetType(), options: SeerrJson.Options);
            }

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeout.Token)
                .ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.Accepted && acceptedMeans is { } accepted)
            {
                throw new SeerrException(accepted);
            }

            if (!response.IsSuccessStatusCode)
            {
                var message = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
                logger.LogInformation("Seerr {Method} {Path}: {Status}", method, logPath, (int)response.StatusCode);
                throw new SeerrException(Classify((int)response.StatusCode, message, asAdmin: asUser is null));
            }

            return await response.Content.ReadFromJsonAsync<T>(SeerrJson.Options, timeout.Token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Seerr {Method} {Path}: nessuna risposta in {Timeout}", method, logPath, Timeout);
            throw new SeerrException(SeerrError.Unavailable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or FormatException)
        {
            // FormatException copre UriFormatException e Headers.Add con una chiave con a capo.
            // Questi messaggi non contengono né la chiave né la query.
            logger.LogWarning("Seerr {Method} {Path} non riuscita: {Error} {Message}", method, logPath, ex.GetType().Name, ex.Message);
            throw new SeerrException(SeerrError.Unavailable, ex);
        }
    }
}
