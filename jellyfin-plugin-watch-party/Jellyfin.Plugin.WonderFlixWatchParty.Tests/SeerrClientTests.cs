using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrClientTests
{
    private readonly FakeSeerrHttp _http = new();
    private readonly FakeSeerrSettings _settings = new() { Url = "https://seerr.example/seerr", ApiKey = "segreta" };
    private readonly RecordingLogger<SeerrClient> _logger = new();

    private SeerrClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? SeerrClient.DefaultTimeout };

    private void Answer(HttpStatusCode status, string json) =>
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(status, json));

    [Fact]
    public async Task EveryCallCarriesTheKeyAndTheUserOnlyWhenActingForSomeone()
    {
        Answer(HttpStatusCode.OK, """{"version":"3.4.1"}""");
        var status = await Client().GetStatusAsync(CancellationToken.None);

        Assert.Equal("3.4.1", status.Version);
        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://seerr.example/seerr/api/v1/status", seen.Uri.OriginalString);
        Assert.Equal("segreta", seen.ApiKey);
        Assert.Null(seen.ApiUser);
        Assert.Equal(SeerrClient.HttpClientName, _http.LastClientName);

        Answer(HttpStatusCode.Created, """{"id":7,"status":1,"type":"tv"}""");
        var created = await Client().CreateRequestAsync(
            12, new SeerrCreateRequest { MediaType = "tv", MediaId = 90228, Seasons = [1] }, CancellationToken.None);

        Assert.Equal(7, created.Id);
        var post = _http.Requests[1];
        Assert.Equal(HttpMethod.Post, post.Method);
        Assert.Equal("https://seerr.example/seerr/api/v1/request", post.Uri.OriginalString);
        Assert.Equal("12", post.ApiUser);
        Assert.Equal("""{"mediaType":"tv","mediaId":90228,"seasons":[1]}""", post.Body);
    }

    [Fact]
    public async Task PathsQueriesAndBodies()
    {
        _http.Respond = (request, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            request.RequestUri!.AbsolutePath.EndsWith("/service/radarr", StringComparison.Ordinal)
                ? "[]"
                : """{"id":1,"status":2,"pageInfo":{"results":0},"results":[]}"""));
        var client = Client();

        await client.SearchAsync("l'ultimo (2)", "it", CancellationToken.None);
        await client.GetRequestsAsync(3, "pending", 20, 40, 3, CancellationToken.None);
        await client.GetRequestsAsync(3, "all", 20, 0, null, CancellationToken.None);
        await client.GetServersAsync(SeerrServices.Radarr, CancellationToken.None);
        await client.GetServerDetailsAsync(SeerrServices.Sonarr, 0, CancellationToken.None);
        await client.GetMovieAsync(438631, "it", CancellationToken.None);
        await client.GetTvAsync(90228, "en", CancellationToken.None);
        await client.GetUsersAsync(CancellationToken.None);
        await client.GetMainSettingsAsync(CancellationToken.None);
        await client.ImportJellyfinUserAsync(Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5"), CancellationToken.None);
        await client.SetRequestStatusAsync(3, 434, approve: true, CancellationToken.None);
        await client.SetRequestStatusAsync(3, 435, approve: false, CancellationToken.None);
        await client.GetRequestAsync(3, 434, CancellationToken.None);
        await client.UpdateRequestAsync(
            3, 434, new SeerrUpdateRequest { MediaType = "movie", ServerId = 1, ProfileId = 7, RootFolder = "/media/anime" },
            CancellationToken.None);

        string Path(int i) => _http.Requests[i].Uri.OriginalString["https://seerr.example/seerr/api/v1/".Length..];
        Assert.Equal("search?query=l%27ultimo%20%282%29&page=1&language=it", Path(0));
        Assert.Equal("request?take=20&skip=40&filter=pending&sort=added&sortDirection=desc&requestedBy=3", Path(1));
        Assert.Equal("3", _http.Requests[1].ApiUser);
        Assert.Equal("request?take=20&skip=0&filter=all&sort=added&sortDirection=desc", Path(2));
        Assert.Equal("service/radarr", Path(3));
        Assert.Null(_http.Requests[3].ApiUser);
        Assert.Equal("service/sonarr/0", Path(4));
        Assert.Equal("movie/438631?language=it", Path(5));
        Assert.Equal("tv/90228?language=en", Path(6));
        Assert.Equal($"user?take={SeerrClient.MaxUsers}&skip=0", Path(7));
        Assert.Equal("settings/main", Path(8));
        Assert.Equal("user/import-from-jellyfin", Path(9));
        Assert.Equal("""{"jellyfinUserIds":["150fe35a657b4c5ea4fd644c4c5152b5"]}""", _http.Requests[9].Body);
        Assert.Equal("request/434/approve", Path(10));
        Assert.Equal(HttpMethod.Post, _http.Requests[10].Method);
        Assert.Equal("request/435/decline", Path(11));
        Assert.Equal("request/434", Path(12));
        Assert.Equal(HttpMethod.Get, _http.Requests[12].Method);
        Assert.Equal(HttpMethod.Put, _http.Requests[13].Method);
        Assert.Equal(
            """{"mediaType":"movie","serverId":1,"profileId":7,"rootFolder":"/media/anime"}""", _http.Requests[13].Body);
    }

    [Theory]
    [InlineData(403, """{"message":"Movie Quota exceeded."}""", false, SeerrError.QuotaExceeded)]
    [InlineData(403, """{"message":"This media is blocklisted."}""", false, SeerrError.Blocklisted)]
    [InlineData(403, """{"message":"You do not have permission to make movie requests."}""", false, SeerrError.NoPermission)]
    [InlineData(403, """{"error":"You do not have permission to access this endpoint"}""", true, SeerrError.Auth)]
    [InlineData(401, "{}", false, SeerrError.Auth)]
    [InlineData(409, "{}", false, SeerrError.AlreadyRequested)]
    [InlineData(404, "{}", false, SeerrError.NotFound)]
    [InlineData(400, "{}", false, SeerrError.BadRequest)]
    [InlineData(500, "{}", false, SeerrError.Unavailable)]
    public void ClassifiesSeerrErrors(int status, string message, bool asAdmin, SeerrError expected) =>
        Assert.Equal(expected, SeerrClient.Classify(status, message, asAdmin));

    [Fact]
    public async Task AnErrorResponseBecomesASeerrExceptionAndTheKeyNeverReachesTheLog()
    {
        Answer(HttpStatusCode.Forbidden, """{"message":"Series Quota exceeded."}""");

        var error = await Assert.ThrowsAsync<SeerrException>(() => Client().CreateRequestAsync(
            5, new SeerrCreateRequest { MediaType = "tv", MediaId = 1, Seasons = [1] }, CancellationToken.None));

        Assert.Equal(SeerrError.QuotaExceeded, error.Error);
        Assert.NotEmpty(_logger.Entries);
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("segreta", StringComparison.Ordinal));
    }

    [Fact]
    public async Task AcceptedOnANewRequestOrAnUpdateMeansNothingToRequest()
    {
        Answer(HttpStatusCode.Accepted, """{"status":202,"message":"No seasons available to request"}""");

        var create = await Assert.ThrowsAsync<SeerrException>(() => Client().CreateRequestAsync(
            1, new SeerrCreateRequest { MediaType = "tv", MediaId = 1, Seasons = [1] }, CancellationToken.None));
        var update = await Assert.ThrowsAsync<SeerrException>(() => Client().UpdateRequestAsync(
            1, 2, new SeerrUpdateRequest { MediaType = "tv", Seasons = [1] }, CancellationToken.None));

        Assert.Equal(SeerrError.NothingToRequest, create.Error);
        Assert.Equal(SeerrError.NothingToRequest, update.Error);
    }

    [Fact]
    public async Task NotConfiguredDoesNotCallSeerr()
    {
        _settings.ApiKey = string.Empty;

        var error = await Assert.ThrowsAsync<SeerrException>(() => Client().GetStatusAsync(CancellationToken.None));

        Assert.Equal(SeerrError.NotConfigured, error.Error);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task NetworkErrorsTimeoutsBadJsonAndBadUrlsAreUnavailable()
    {
        async Task<SeerrError> ErrorOf(SeerrClient client) =>
            (await Assert.ThrowsAsync<SeerrException>(() => client.GetStatusAsync(CancellationToken.None))).Error;

        _http.Respond = (_, _) => throw new HttpRequestException("rete");
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));

        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "{}");
        };
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client(TimeSpan.FromMilliseconds(50))));

        Answer(HttpStatusCode.OK, "<html>");
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));

        _settings.Url = "seerr-senza-schema";
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));
    }

    [Fact]
    public async Task ACancelledCallerGetsTheCancellation()
    {
        using var cancel = new CancellationTokenSource();
        _http.Respond = async (_, ct) =>
        {
            await cancel.CancelAsync();
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "{}");
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client().GetStatusAsync(cancel.Token));
    }
}
