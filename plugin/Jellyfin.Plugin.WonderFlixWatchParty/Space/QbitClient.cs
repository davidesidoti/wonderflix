using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
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

    /// <summary>Quanto si aspetta che un <c>.torrent</c> aggiunto compaia; i test la accorciano.</summary>
    internal TimeSpan AddWait { get; init; } = TimeSpan.FromSeconds(60);

    /// <summary>Ogni quanto si guarda se è comparso; i test la azzerano.</summary>
    internal TimeSpan AddPoll { get; init; } = TimeSpan.FromSeconds(1);

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

    public async Task<IReadOnlyList<QbitLogEntry>> GetLogAsync(CancellationToken cancellationToken) =>
        await SendAsync(
            HttpMethod.Get, "log/main?normal=true&info=false&warning=false&critical=false", null, ReadListAsync<QbitLogEntry>, cancellationToken)
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

    public async Task<string> AddAsync(string link, string category, CancellationToken cancellationToken)
    {
        // Un tag unico ritrova il torrent quando l'hash non si legge dal magnet.
        var tag = "wf-" + RandomNumberGenerator.GetHexString(8, lowercase: true);
        byte[]? torrent = null;
        if (!link.StartsWith("magnet:", StringComparison.OrdinalIgnoreCase))
        {
            (link, torrent) = await FetchTorrentAsync(link, cancellationToken).ConfigureAwait(false);
        }

        var form = new Dictionary<string, string> { ["category"] = category, ["tags"] = "wonderflix," + tag };
        if (torrent is null)
        {
            form["urls"] = link;
        }

        await SendAsync(HttpMethod.Post, "torrents/add", form, ReadAddedAsync, cancellationToken, torrent).ConfigureAwait(false);
        return (torrent is null ? HashOfMagnet(link) : null) ?? await FindByTagAsync(tag, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>L'hash (40 cifre esadecimali, minuscolo) di un magnet <c>xt=urn:btih:</c>, anche in base32; null se non c'è.</summary>
    internal static string? HashOfMagnet(string magnet)
    {
        const string Prefix = "urn:btih:";
        var start = magnet.IndexOf(Prefix, StringComparison.OrdinalIgnoreCase);
        if (start < 0)
        {
            return null;
        }

        var value = magnet[(start + Prefix.Length)..].Split('&')[0];
        if (value.Length == 40 && value.All(Uri.IsHexDigit))
        {
            return value.ToLowerInvariant();
        }

        if (value.Length != 32)
        {
            return null;
        }

        // Base32 (RFC 4648): 32 caratteri da 5 bit sono i 20 byte dell'hash.
        var bytes = new byte[20];
        var (buffer, bits, index) = (0, 0, 0);
        foreach (var c in value.ToUpperInvariant())
        {
            var digit = c is >= 'A' and <= 'Z' ? c - 'A' : c is >= '2' and <= '7' ? c - '2' + 26 : -1;
            if (digit < 0)
            {
                return null;
            }

            buffer = ((buffer << 5) | digit) & 0xFFF;
            bits += 5;
            if (bits >= 8)
            {
                bits -= 8;
                bytes[index++] = (byte)(buffer >> bits);
            }
        }

        return Convert.ToHexStringLower(bytes);
    }

    // qBittorrent risponde 200 anche quando non aggiunge: "Fails.".
    private static async Task<bool> ReadAddedAsync(HttpResponseMessage response, CancellationToken cancellationToken) =>
        (await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false)).Trim() != "Fails."
            ? true
            : throw new QbitException(QbitError.Unreachable);

    /// <summary>
    /// Scarica il <c>.torrent</c> (da Prowlarr): un redirect a un magnet dà il magnet, altrimenti i byte. Mai il link nel
    /// registro: contiene la chiave di Prowlarr.
    /// </summary>
    private async Task<(string Link, byte[]? Torrent)> FetchTorrentAsync(string url, CancellationToken cancellationToken)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(Timeout);
        try
        {
            // Pochi redirect a mano: il client non li segue (e non seguirebbe mai un magnet).
            for (var hop = 0; hop < 4; hop++)
            {
                using var response = await httpClientFactory.CreateClient(ArrClient.HttpClientName)
                    .GetAsync(url, timeoutSource.Token)
                    .ConfigureAwait(false);
                if ((int)response.StatusCode is >= 300 and < 400 && response.Headers.Location is { } location)
                {
                    var next = location.IsAbsoluteUri ? location : new Uri(new Uri(url), location);
                    if (string.Equals(next.Scheme, "magnet", StringComparison.OrdinalIgnoreCase))
                    {
                        return (next.OriginalString, null);
                    }

                    url = next.AbsoluteUri;
                    continue;
                }

                if (!response.IsSuccessStatusCode)
                {
                    logger.LogWarning("Download del .torrent non riuscito: {Status}", (int)response.StatusCode);
                    throw new QbitException(QbitError.Unreachable);
                }

                return (url, await response.Content.ReadAsByteArrayAsync(timeoutSource.Token).ConfigureAwait(false));
            }

            logger.LogWarning("Download del .torrent non riuscito: troppi redirect");
            throw new QbitException(QbitError.Unreachable);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download del .torrent: nessuna risposta in {Timeout}", Timeout);
            throw new QbitException(QbitError.Unreachable);
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or FormatException)
        {
            // Solo il tipo: il messaggio può contenere l'indirizzo.
            logger.LogWarning("Download del .torrent non riuscito: {Error}", ex.GetType().Name);
            throw new QbitException(QbitError.Unreachable, ex);
        }
    }

    /// <summary>Il torrent aggiunto col tag unico, appena compare; <see cref="QbitError.NotFound"/> se non compare entro <see cref="AddWait"/>.</summary>
    private async Task<string> FindByTagAsync(string tag, CancellationToken cancellationToken)
    {
        var watch = Stopwatch.StartNew();
        while (true)
        {
            var found = await SendAsync(
                HttpMethod.Get, "torrents/info?tag=" + Uri.EscapeDataString(tag), null, ReadListAsync<QbitTorrent>, cancellationToken)
                .ConfigureAwait(false);
            if (found.FirstOrDefault(t => !string.IsNullOrEmpty(t.Hash)) is { } torrent)
            {
                return torrent.Hash!.ToLowerInvariant();
            }

            if (watch.Elapsed >= AddWait)
            {
                logger.LogWarning("qBittorrent: il torrent aggiunto non è comparso in {Wait}", AddWait);
                throw new QbitException(QbitError.NotFound);
            }

            await Task.Delay(AddPoll, cancellationToken).ConfigureAwait(false);
        }
    }

    private static async Task<IReadOnlyList<T>> ReadListAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken) =>
        await response.Content.ReadFromJsonAsync<List<T>>(JsonOptions, cancellationToken).ConfigureAwait(false)
        ?? throw new JsonException("risposta vuota");

    /// <summary>Una chiamata con login al primo uso; dopo un 403 si rifà il login e si ripete una volta sola.</summary>
    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        Dictionary<string, string>? form,
        Func<HttpResponseMessage, CancellationToken, Task<T>> read,
        CancellationToken cancellationToken,
        byte[]? torrent = null)
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
                if (torrent is not null)
                {
                    // Un .torrent viaggia come file "torrents" in un multipart, con gli altri campi accanto.
                    var multipart = new MultipartFormDataContent();
                    foreach (var (name, value) in form ?? new Dictionary<string, string>())
                    {
                        multipart.Add(new StringContent(value), name);
                    }

                    multipart.Add(new ByteArrayContent(torrent), "torrents", "wonderflix.torrent");
                    request.Content = multipart;
                }
                else if (form is not null)
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
