using System.Net;
using System.Text;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class QbitClientTests
{
    private const string Torrents = """
        [{"hash":"abcdef0123456789","name":"Film.2026.1080p","size":5000000000,"progress":1,"ratio":1.5,
          "seeding_time":864000,"tracker":"https://tracker.example/announce","state":"stalledUP",
          "save_path":"/srv/seedings","content_path":"/srv/seedings/Film.2026.1080p"}]
        """;

    private readonly FakeSeerrHttp _http = new();
    private readonly FakeSpaceSettings _settings = new() { QbitUrl = "http://qbit.example", QbitUser = "u", QbitPassword = "s3cretpw" };
    private readonly RecordingLogger<QbitClient> _logger = new();
    private readonly List<string?> _cookies = [];

    private QbitClient Client() => new(_http, _settings, _logger);

    private static HttpResponseMessage Login(string body = "Ok.", string? cookie = "SID=abc123; HttpOnly; path=/")
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "text/plain") };
        if (cookie is not null)
        {
            response.Headers.Add("Set-Cookie", cookie);
        }

        return response;
    }

    // Le risposte per percorso: ogni elemento serve una volta, l'ultimo resta; ricorda il cookie di ogni richiesta.
    private void Script(Dictionary<string, Queue<Func<HttpResponseMessage>>> routes) =>
        _http.Respond = (request, _) =>
        {
            _cookies.Add(request.Headers.TryGetValues("Cookie", out var values) ? values.Single() : null);
            var queue = routes[request.RequestUri!.AbsolutePath];
            return Task.FromResult(queue.Count > 1 ? queue.Dequeue()() : queue.Peek()());
        };

    private static Queue<Func<HttpResponseMessage>> Seq(params Func<HttpResponseMessage>[] items) => new(items);

    private static HttpResponseMessage Status(HttpStatusCode status) => new(status);

    private static HttpResponseMessage JsonOk(string json) => FakeSeerrHttp.Json(HttpStatusCode.OK, json);

    private int Logins => _http.Requests.Count(r => r.Uri.AbsolutePath.EndsWith("/login", StringComparison.Ordinal));

    [Fact]
    public async Task LoginThenListTorrents()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/info"] = Seq(() => JsonOk(Torrents)),
        });

        var torrents = await Client().GetTorrentsAsync(CancellationToken.None);

        Assert.Equal(2, _http.Requests.Count);
        Assert.Equal(HttpMethod.Post, _http.Requests[0].Method);
        Assert.Equal("http://qbit.example/api/v2/auth/login", _http.Requests[0].Uri.ToString());
        Assert.Equal("username=u&password=s3cretpw", _http.Requests[0].Body);
        Assert.Equal(HttpMethod.Get, _http.Requests[1].Method);
        Assert.Equal("http://qbit.example/api/v2/torrents/info", _http.Requests[1].Uri.ToString());
        Assert.Equal("SID=abc123", _cookies[1]);
        Assert.Equal(QbitClient.HttpClientName, _http.LastClientName);
        var torrent = Assert.Single(torrents);
        Assert.Equal("abcdef0123456789", torrent.Hash);
        Assert.Equal("Film.2026.1080p", torrent.Name);
        Assert.Equal(5000000000, torrent.Size);
        Assert.Equal(1.5, torrent.Ratio);
        Assert.Equal(864000, torrent.SeedingTime);
        Assert.Equal("stalledUP", torrent.State);
        Assert.Equal("/srv/seedings", torrent.SavePath);
        Assert.Equal("/srv/seedings/Film.2026.1080p", torrent.ContentPath);
    }

    [Fact]
    public async Task TheSessionIsKeptBetweenCalls()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/info"] = Seq(() => JsonOk(Torrents)),
        });
        var client = Client();

        await client.GetTorrentsAsync(CancellationToken.None);
        await client.GetTorrentsAsync(CancellationToken.None);

        Assert.Equal(1, Logins);
    }

    [Fact]
    public async Task AnExpiredCookieLogsInAgainOnce()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login(cookie: "SID=first"), () => Login(cookie: "SID=second")),
            ["/api/v2/torrents/info"] = Seq(() => Status(HttpStatusCode.Forbidden), () => JsonOk(Torrents)),
        });

        var torrents = await Client().GetTorrentsAsync(CancellationToken.None);

        Assert.Single(torrents);
        Assert.Equal(2, Logins);
        Assert.Equal("SID=second", _cookies[^1]);
    }

    [Fact]
    public async Task ASecondForbiddenIsUnauthorized()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/info"] = Seq(() => Status(HttpStatusCode.Forbidden)),
        });

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unauthorized, ex.Error);
        Assert.Equal(4, _http.Requests.Count); // login, info, login, info: mai un terzo tentativo
    }

    [Fact]
    public async Task WrongPasswordIsUnauthorized()
    {
        Script(new() { ["/api/v2/auth/login"] = Seq(() => Login("Fails.", "SID=x")) });

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unauthorized, ex.Error);
    }

    [Fact]
    public async Task ALoginWithoutTheSessionCookieIsUnauthorized()
    {
        Script(new() { ["/api/v2/auth/login"] = Seq(() => Login("Ok.", null)) });

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unauthorized, ex.Error);
    }

    [Fact]
    public async Task AForbiddenLoginIsUnauthorized()
    {
        Script(new() { ["/api/v2/auth/login"] = Seq(() => Status(HttpStatusCode.Forbidden)) });

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unauthorized, ex.Error);
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    public async Task WithoutAnAddressNothingIsCalled(string url)
    {
        _settings.QbitUrl = url;

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.NotConfigured, ex.Error);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task AServerErrorIsUnreachable()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/info"] = Seq(() => Status(HttpStatusCode.BadGateway)),
        });

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unreachable, ex.Error);
    }

    [Fact]
    public async Task ADeadNetworkIsUnreachable()
    {
        _http.Respond = (_, _) => throw new HttpRequestException("rifiutata");

        var ex = await Assert.ThrowsAsync<QbitException>(() => Client().GetTorrentsAsync(CancellationToken.None));

        Assert.Equal(QbitError.Unreachable, ex.Error);
    }

    [Fact]
    public async Task FilesAskForTheHashAndANotFoundTrackerListIsNotFound()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/files"] = Seq(() => JsonOk("""[{"name":"Film/a.mkv","size":42}]""")),
            ["/api/v2/torrents/trackers"] = Seq(() => Status(HttpStatusCode.NotFound)),
        });
        var client = Client();

        var files = await client.GetFilesAsync("abc", CancellationToken.None);
        var ex = await Assert.ThrowsAsync<QbitException>(() => client.GetTrackersAsync("abc", CancellationToken.None));

        var file = Assert.Single(files);
        Assert.Equal("Film/a.mkv", file.Name);
        Assert.Equal(42, file.Size);
        Assert.Equal(QbitError.NotFound, ex.Error);
        Assert.Contains(_http.Requests, r => r.Uri.ToString() == "http://qbit.example/api/v2/torrents/files?hash=abc");
    }

    [Fact]
    public async Task TrackersAreRead()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/trackers"] = Seq(() => JsonOk("""[{"url":"** [DHT] **"},{"url":"https://t.example/announce"}]""")),
        });

        var trackers = await Client().GetTrackersAsync("abc", CancellationToken.None);

        Assert.Equal(["** [DHT] **", "https://t.example/announce"], trackers.Select(t => t.Url));
    }

    [Theory]
    [InlineData(true, "hashes=a%7Cb&deleteFiles=true")]
    [InlineData(false, "hashes=a%7Cb&deleteFiles=false")]
    public async Task DeleteSendsHashesAndTheFilesFlag(bool deleteFiles, string body)
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/delete"] = Seq(() => Status(HttpStatusCode.OK)),
        });

        await Client().DeleteAsync(["a", "b"], deleteFiles, CancellationToken.None);

        var delete = _http.Requests.Single(r => r.Uri.AbsolutePath.EndsWith("/delete", StringComparison.Ordinal));
        Assert.Equal(HttpMethod.Post, delete.Method);
        Assert.Equal(body, delete.Body);
    }

    [Fact]
    public async Task DeletingNothingCallsNothing()
    {
        await Client().DeleteAsync([], true, CancellationToken.None);

        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task ThePasswordTheCookieAndTheHashNeverReachTheLog()
    {
        Script(new()
        {
            ["/api/v2/auth/login"] = Seq(() => Login()),
            ["/api/v2/torrents/info"] = Seq(() => Status(HttpStatusCode.Forbidden)),
            ["/api/v2/torrents/files"] = Seq(() => Status(HttpStatusCode.NotFound)),
        });
        var client = Client();

        await Assert.ThrowsAsync<QbitException>(() => client.GetTorrentsAsync(CancellationToken.None));
        await Assert.ThrowsAsync<QbitException>(() => client.GetFilesAsync("0123456789abcdef", CancellationToken.None));

        Assert.NotEmpty(_logger.Entries);
        foreach (var (_, _, message) in _logger.Entries)
        {
            Assert.DoesNotContain("s3cretpw", message, StringComparison.Ordinal);
            Assert.DoesNotContain("abc123", message, StringComparison.Ordinal);
            Assert.DoesNotContain("SID", message, StringComparison.Ordinal);
            Assert.DoesNotContain("0123456789abcdef", message, StringComparison.Ordinal);
        }
    }
}
