using System.Net;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Una richiesta vista da <see cref="FakeDiscordHttp"/>.</summary>
internal sealed record DiscordRequest(HttpMethod Method, string PathAndQuery, string? Authorization, string? UserAgent, string? Body);

/// <summary>HTTP finto per DiscordBotClient: registra le richieste e risponde con <see cref="Respond"/>.</summary>
internal sealed class FakeDiscordHttp : HttpMessageHandler, IHttpClientFactory
{
    public List<DiscordRequest> Requests { get; } = [];

    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Respond { get; set; } =
        (_, _) => Task.FromResult(Json(HttpStatusCode.OK, "{}"));

    /// <summary>Il nome con cui DiscordBotClient ha chiesto l'ultimo client.</summary>
    public string? LastClientName { get; private set; }

    public HttpClient CreateClient(string name)
    {
        LastClientName = name;
        return new HttpClient(this, disposeHandler: false);
    }

    public static HttpResponseMessage Json(HttpStatusCode status, string json) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new DiscordRequest(
            request.Method, request.RequestUri!.PathAndQuery, Header(request, "Authorization"), Header(request, "User-Agent"), body));
        return await Respond(request, cancellationToken);
    }

    private static string? Header(HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? string.Join(" ", values) : null;
}
