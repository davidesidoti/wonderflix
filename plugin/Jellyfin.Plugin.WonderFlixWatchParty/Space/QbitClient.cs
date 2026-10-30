using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// HTTP verso qBittorrent (WebUI API v2). Il login serve sempre, anche da localhost; il cookie <c>SID</c> si tiene in
/// memoria e si rifà una volta sola se scade (spec U §7.2). Nel registro vanno solo metodo, percorso ed esito:
/// mai password, cookie, query, nomi o hash.
/// </summary>
public sealed class QbitClient(
    IHttpClientFactory httpClientFactory,
    ISpaceSettings settings,
    ILogger<QbitClient> logger) : IQbitClient
{
    /// <summary>Nome del client HTTP registrato nel DI (senza cookie automatici: il SID lo gestisce questa classe).</summary>
    public const string HttpClientName = "WonderFlixQbit";

    /// <summary>Attesa massima di una chiamata, login compreso.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly Lock _sidLock = new();
    private string? _sid;

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public async Task<IReadOnlyList<QbitTorrent>> GetTorrentsAsync(CancellationToken cancellationToken) =>
        await SendAsync(HttpMethod.Get, "torrents/info", null, ReadListAsync<QbitTorrent>, cancellationToken).ConfigureAwait(false);

    public async Task<IReadOnlyList<QbitFile>> GetFilesAsync(string hash, CancellationToken cancellationToken) =>
        await SendAsync(
            HttpMethod.Get, "torrents/files?hash=" + Uri.EscapeDataString(hash), null, ReadListAsync<QbitFile>, cancellationToken)
            .ConfigureAwait(false);

    public async Task<IReadOnlyList<QbitTracker>> GetTrackersAsync(string hash, CancellationToken cancellationToken) =>
        await SendAsync(
            HttpMethod.Get, "torrents/trackers?hash=" + Uri.EscapeDataString(hash), null, ReadListAsync<QbitTracker>, cancellationToken)
            .ConfigureAwait(false);

    public Task DeleteAsync(IReadOnlyList<string> hashes, bool deleteFiles, CancellationToken cancellationToken) =>
        hashes.Count == 0
            ? Task.CompletedTask
            : SendAsync(
                HttpMethod.Post,
                "torrents/delete",
                new Dictionary<string, string> { ["hashes"] = string.Join('|', hashes), ["deleteFiles"] = deleteFiles ? "true" : "false" },
                (_, _) => Task.FromResult(true),
                cancellationToken);

    private static async Task<IReadOnlyList<T>> ReadListAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken) =>
        await response.Content.ReadFromJsonAsync<List<T>>(JsonOptions, cancellationToken).ConfigureAwait(false)
        ?? throw new JsonException("risposta vuota");

    /// <summary>Una chiamata con login al primo uso; dopo un 403 si rifà il login e si ripete una volta sola.</summary>
    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        Dictionary<string, string>? form,
        Func<HttpResponseMessage, CancellationToken, Task<T>> read,
        CancellationToken cancellationToken)
    {
        var baseUrl = settings.QbitUrl?.Trim().TrimEnd('/');
        if (string.IsNullOrEmpty(baseUrl))
        {
            throw new QbitException(QbitError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(Timeout);
        try
        {
            for (var attempt = 0; ; attempt++)
            {
                string sid;
                lock (_sidLock)
                {
                    sid = _sid ?? string.Empty;
                }

                if (sid.Length == 0)
                {
                    sid = await LoginAsync(baseUrl, timeoutSource.Token).ConfigureAwait(false);
                }

                using var request = new HttpRequestMessage(method, $"{baseUrl}/api/v2/{path}");
                request.Headers.TryAddWithoutValidation("Cookie", "SID=" + sid);
                if (form is not null)
                {
                    request.Content = new FormUrlEncodedContent(form);
                }

                using var response = await httpClientFactory.CreateClient(HttpClientName)
                    .SendAsync(request, timeoutSource.Token)
                    .ConfigureAwait(false);
                if (response.StatusCode == HttpStatusCode.Forbidden)
                {
                    // Il cookie è scaduto (o il server è stato riavviato): si butta e si rifà il login.
                    lock (_sidLock)
                    {
                        _sid = null;
                    }

                    logger.LogInformation("qBittorrent {Method} {Path}: 403 (tentativo {Attempt})", method, logPath, attempt + 1);
                    if (attempt == 1)
                    {
                        throw new QbitException(QbitError.Unauthorized);
                    }

                    continue;
                }

                if (!response.IsSuccessStatusCode)
                {
                    logger.LogInformation("qBittorrent {Method} {Path}: {Status}", method, logPath, (int)response.StatusCode);
                    throw new QbitException(response.StatusCode == HttpStatusCode.NotFound ? QbitError.NotFound : QbitError.Unreachable);
                }

                return await read(response, timeoutSource.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("qBittorrent {Method} {Path}: nessuna risposta in {Timeout}", method, logPath, Timeout);
            throw new QbitException(QbitError.Unreachable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or FormatException)
        {
            // FormatException copre UriFormatException. Questi messaggi non contengono né la password né il cookie.
            logger.LogWarning(
                "qBittorrent {Method} {Path} non riuscita: {Error} {Message}", method, logPath, ex.GetType().Name, ex.Message);
            throw new QbitException(QbitError.Unreachable, ex);
        }
    }

    /// <summary>Il login: <c>Ok.</c> più il cookie <c>SID</c>. Tiene il cookie in memoria e lo restituisce.</summary>
    private async Task<string> LoginAsync(string baseUrl, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/api/v2/auth/login")
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["username"] = settings.QbitUser,
                ["password"] = settings.QbitPassword,
            }),
        };
        using var response = await httpClientFactory.CreateClient(HttpClientName)
            .SendAsync(request, cancellationToken)
            .ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.Forbidden)
        {
            // Troppi tentativi sbagliati: qBittorrent blocca l'indirizzo per un po'.
            logger.LogWarning("qBittorrent login: 403");
            throw new QbitException(QbitError.Unauthorized);
        }

        if (!response.IsSuccessStatusCode)
        {
            logger.LogWarning("qBittorrent login: {Status}", (int)response.StatusCode);
            throw new QbitException(QbitError.Unreachable);
        }

        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var sid = response.Headers.TryGetValues("Set-Cookie", out var cookies)
            ? cookies.Select(SidOf).FirstOrDefault(value => value is not null)
            : null;
        if (body.Trim() != "Ok." || sid is null)
        {
            logger.LogWarning("qBittorrent login rifiutato");
            throw new QbitException(QbitError.Unauthorized);
        }

        lock (_sidLock)
        {
            _sid = sid;
        }

        return sid;
    }

    /// <summary>Il valore di <c>SID</c> in una riga <c>Set-Cookie</c>, o null se è un altro cookie.</summary>
    private static string? SidOf(string setCookie)
    {
        const string Prefix = "SID=";
        if (!setCookie.StartsWith(Prefix, StringComparison.Ordinal))
        {
            return null;
        }

        var value = setCookie[Prefix.Length..].Split(';')[0].Trim();
        return value.Length == 0 ? null : value;
    }
}
