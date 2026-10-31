using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HttpPushTransportTests
{
    private const string Endpoint = "https://push.example.com/send/secret-token";
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeDiscordHttp _http = new();
    private readonly RecordingLogger<HttpPushTransport> _logger = new();
    private readonly FakeTimeProvider _time = new();

    private HttpPushTransport Transport() => new(_http, _logger) { Time = _time };

    private static PushSubscription Sub() => new() { UserId = Guid.NewGuid(), Endpoint = Endpoint };

    [Fact]
    public async Task Send_PostsEncryptedBodyWithHeaders()
    {
        byte[]? body = null;
        HttpRequestMessage? seen = null;
        _http.Respond = async (request, ct) =>
        {
            seen = request;
            body = await request.Content!.ReadAsByteArrayAsync(ct);
            return new HttpResponseMessage(HttpStatusCode.Created);
        };

        var result = await Transport().SendAsync(Sub(), [1, 2, 3], "vapid t=a, k=b", Ct);

        Assert.Equal(PushResult.Sent, result);
        Assert.Equal(HttpMethod.Post, seen!.Method);
        Assert.Equal(Endpoint, seen.RequestUri!.ToString());
        Assert.Equal(HttpPushTransport.HttpClientName, _http.LastClientName);
        Assert.Equal([1, 2, 3], body);
        Assert.Equal("aes128gcm", Assert.Single(seen.Content!.Headers.ContentEncoding));
        Assert.Equal("application/octet-stream", seen.Content.Headers.ContentType!.MediaType);
        Assert.Equal("86400", Assert.Single(seen.Headers.GetValues("TTL")));
        Assert.Equal("normal", Assert.Single(seen.Headers.GetValues("Urgency")));
        Assert.Equal("vapid t=a, k=b", Assert.Single(seen.Headers.GetValues("Authorization")));
    }

    [Theory]
    [InlineData(HttpStatusCode.NotFound)]
    [InlineData(HttpStatusCode.Gone)]
    public async Task Send_404And410AreGone(HttpStatusCode status)
    {
        _http.Respond = (_, _) => Task.FromResult(new HttpResponseMessage(status));
        Assert.Equal(PushResult.Gone, await Transport().SendAsync(Sub(), [1], "x", Ct));
    }

    [Theory]
    [InlineData(HttpStatusCode.InternalServerError)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    [InlineData(HttpStatusCode.BadRequest)]
    public async Task Send_5xxAndOtherErrorsAreFailed(HttpStatusCode status)
    {
        _http.Respond = (_, _) => Task.FromResult(new HttpResponseMessage(status));
        Assert.Equal(PushResult.Failed, await Transport().SendAsync(Sub(), [1], "x", Ct));
    }

    [Fact]
    public async Task Send_TimeoutIsFailedAndLogsOnlyTheHost()
    {
        _http.Respond = async (_, ct) =>
        {
            _time.Advance(HttpPushTransport.DefaultTimeout);
            await Task.Delay(Timeout.Infinite, ct);
            return new HttpResponseMessage(HttpStatusCode.Created);
        };

        Assert.Equal(PushResult.Failed, await Transport().SendAsync(Sub(), [1], "x", Ct));
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("secret-token"));
        Assert.Contains(_logger.Entries, e => e.Message.Contains("push.example.com"));
    }

    [Fact]
    public async Task Send_CallerCancellationPropagates()
    {
        using var cts = new CancellationTokenSource();
        _http.Respond = async (_, ct) =>
        {
            await cts.CancelAsync();
            await Task.Delay(Timeout.Infinite, ct);
            return new HttpResponseMessage(HttpStatusCode.Created);
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Transport().SendAsync(Sub(), [1], "x", cts.Token));
    }
}
