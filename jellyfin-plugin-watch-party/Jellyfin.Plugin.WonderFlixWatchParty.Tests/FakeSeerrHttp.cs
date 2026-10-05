using System.Net;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Una richiesta vista da <see cref="FakeSeerrHttp"/>.</summary>
internal sealed record SeenRequest(HttpMethod Method, Uri Uri, string? ApiKey, string? ApiUser, string? Body);

/// <summary>HTTP finto per SeerrClient: registra le richieste e risponde con <see cref="Respond"/>.</summary>
internal sealed class FakeSeerrHttp : HttpMessageHandler, IHttpClientFactory
{
    public List<SeenRequest> Requests { get; } = [];

    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Respond { get; set; } =
        (_, _) => Task.FromResult(Json(HttpStatusCode.OK, "{}"));

    /// <summary>Il nome con cui SeerrClient ha chiesto l'ultimo client.</summary>
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
        Requests.Add(new SeenRequest(
            request.Method, request.RequestUri!, Header(request, "X-API-Key"), Header(request, "X-API-User"), body));
        return await Respond(request, cancellationToken);
    }

    private static string? Header(HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? values.Single() : null;
}
