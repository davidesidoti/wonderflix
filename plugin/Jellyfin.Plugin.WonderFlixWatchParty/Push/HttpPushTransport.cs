using System.Net.Http.Headers;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>
/// Il POST Web Push (RFC 8030) all'endpoint dell'iscrizione. Il corpo è già
/// cifrato e l'intestazione VAPID già firmata. Nel registro solo l'host
/// dell'endpoint e l'esito: l'URL intero identifica il browser.
/// </summary>
public sealed class HttpPushTransport(IHttpClientFactory httpClientFactory, ILogger<HttpPushTransport> logger) : IPushTransport
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixPush";

    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Attesa massima di un invio; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    /// <summary>Il tempo su cui scade <see cref="Timeout"/>; i test lo fanno avanzare a mano.</summary>
    internal TimeProvider Time { get; init; } = TimeProvider.System;

    public async Task<PushResult> SendAsync(PushSubscription sub, byte[] body, string authorization, CancellationToken ct)
    {
        var host = Uri.TryCreate(sub.Endpoint, UriKind.Absolute, out var uri) ? uri.Host : "?";
        using var deadline = new CancellationTokenSource(Timeout, Time);
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token, ct);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, sub.Endpoint) { Content = new ByteArrayContent(body) };
            request.Headers.TryAddWithoutValidation("Authorization", authorization);
            request.Headers.TryAddWithoutValidation("TTL", "86400");
            request.Headers.TryAddWithoutValidation("Urgency", "normal");
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            request.Content.Headers.ContentEncoding.Add("aes128gcm");

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, budget.Token)
                .ConfigureAwait(false);
            if (response.IsSuccessStatusCode)
            {
                return PushResult.Sent;
            }

            var status = (int)response.StatusCode;
            logger.LogInformation("Push a {Host}: {Status}", host, status);
            return status is 404 or 410 ? PushResult.Gone : PushResult.Failed;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning("Push a {Host}: nessuna risposta in {Timeout}", host, Timeout);
            return PushResult.Failed;
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or FormatException)
        {
            // I messaggi di queste eccezioni possono contenere l'URL: nel registro solo il tipo.
            logger.LogWarning("Push a {Host} non riuscito: {Error}", host, ex.GetType().Name);
            return PushResult.Failed;
        }
    }
}
