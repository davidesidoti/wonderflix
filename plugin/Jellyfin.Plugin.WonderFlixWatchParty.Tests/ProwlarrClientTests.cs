using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ProwlarrClientTests
{
    private readonly FakeSeerrHttp _http = new();
    private readonly FakeArrSettings _settings = new();
    private readonly RecordingLogger<ProwlarrClient> _logger = new();

    private ProwlarrClient Client() => new(_http, _settings, _logger);

    [Fact]
    public async Task SearchSendsTitleIndexersAndCategories()
    {
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(HttpStatusCode.OK, "[]"));

        await Client().SearchAsync(new("tvsearch", "Slime", 2, null, [8, 11], [5070, 5000]), CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, seen.Method);
        Assert.Equal(
            "https://arr.example/prowlarr/api/v1/search?type=tvsearch&query=Slime&season=2"
            + "&indexerIds=8&indexerIds=11&categories=5070&categories=5000",
            seen.Uri.OriginalString);
        Assert.Equal("prowlarr-key", seen.ApiKey);
        Assert.Equal(ArrClient.HttpClientName, _http.LastClientName);
    }

    [Fact]
    public async Task SearchEscapesTheQueryAndSendsTheEpisode()
    {
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(HttpStatusCode.OK, "[]"));

        await Client().SearchAsync(new("search", "Tensei & Co", null, 3, [], []), CancellationToken.None);

        Assert.Equal(
            "https://arr.example/prowlarr/api/v1/search?type=search&query=Tensei%20%26%20Co&ep=3",
            Assert.Single(_http.Requests).Uri.OriginalString);
    }

    [Fact]
    public async Task SearchParsesReleases()
    {
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            """
            [{"guid":"g","indexerId":8,"indexer":"Nyaa.si","title":"T","size":123,"seeders":4,
              "magnetUrl":"magnet:?x","protocol":"torrent","publishDate":"2026-11-01T00:00:00Z"}]
            """));

        var releases = await Client().SearchAsync(new("search", "x", null, null, [], []), CancellationToken.None);

        var release = Assert.Single(releases);
        Assert.Equal("g", release.Guid);
        Assert.Equal(8, release.IndexerId);
        Assert.Equal("Nyaa.si", release.Indexer);
        Assert.Equal("T", release.Title);
        Assert.Equal(123, release.Size);
        Assert.Equal(4, release.Seeders);
        Assert.Null(release.DownloadUrl);
        Assert.Equal("magnet:?x", release.MagnetUrl);
        Assert.Equal("torrent", release.Protocol);
        Assert.Equal(new DateTimeOffset(2026, 11, 1, 0, 0, 0, TimeSpan.Zero), release.PublishDate);
    }

    [Fact]
    public async Task NotConfiguredThrows()
    {
        _settings.Prowlarr = ArrEndpoint.None;

        var ex = await Assert.ThrowsAsync<ArrException>(
            () => Client().SearchAsync(new("search", "x", null, null, [], []), CancellationToken.None));

        Assert.Equal(ArrError.NotConfigured, ex.Error);
        Assert.Empty(_http.Requests);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, ArrError.Unauthorized)]
    [InlineData(HttpStatusCode.InternalServerError, ArrError.Unreachable)]
    public async Task AFailedAnswerIsClassifiedAndLogsNoKeyOrQuery(HttpStatusCode status, ArrError expected)
    {
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(status, "{}"));

        var ex = await Assert.ThrowsAsync<ArrException>(
            () => Client().SearchAsync(new("search", "secret-title", null, null, [], []), CancellationToken.None));

        Assert.Equal(expected, ex.Error);
        Assert.Equal((int)status, ex.Status);
        Assert.NotEmpty(_logger.Entries);
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("prowlarr-key") || e.Message.Contains("secret-title"));
    }
}
