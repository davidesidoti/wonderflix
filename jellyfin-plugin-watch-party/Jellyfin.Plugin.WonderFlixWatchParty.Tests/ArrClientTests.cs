using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ArrClientTests
{
    private static readonly DateTimeOffset From = new(2026, 10, 10, 2, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset To = new(2026, 10, 17, 14, 0, 0, TimeSpan.Zero);

    // Una voce del calendario di Sonarr 4 come arriva dal server (2026-10-10), accorciata.
    private const string SonarrCalendar = """
        [{"seriesId":12,"tvdbId":10834101,"episodeFileId":0,"seasonNumber":1,"episodeNumber":5,"title":"Episode 5",
          "airDate":"2026-10-11","airDateUtc":"2026-10-12T01:00:00Z","runtime":0,"hasFile":false,"monitored":true,
          "unverifiedSceneNumbering":false,
          "series":{"title":"American Hostage","sortTitle":"american hostage","status":"continuing","ended":false,
            "network":"FX","airTime":"21:00",
            "images":[
              {"coverType":"banner","url":"/sonarr/MediaCover/12/banner.jpg","remoteUrl":"https://artworks.thetvdb.com/b.jpg"},
              {"coverType":"poster","url":"/sonarr/MediaCover/12/poster.jpg","remoteUrl":"https://artworks.thetvdb.com/p.jpg"},
              {"coverType":"fanart","url":"/sonarr/MediaCover/12/fanart.jpg","remoteUrl":"https://artworks.thetvdb.com/f.jpg"}],
            "seasons":[{"seasonNumber":1,"monitored":true}],"year":2026,"path":"/media/tv/American Hostage",
            "tvdbId":462907,"tvRageId":0,"tvMazeId":0,"tmdbId":239618,"imdbId":"tt1234567","id":12}}]
        """;

    // Una voce del calendario di Radarr 6, accorciata.
    private const string RadarrCalendar = """
        [{"title":"Hope","originalTitle":"Hope","year":2026,"tmdbId":1058424,"imdbId":"tt0000001",
          "inCinemas":"2026-07-15T00:00:00Z","digitalRelease":"2026-10-13T00:00:00Z","hasFile":false,"monitored":true,
          "isAvailable":true,
          "images":[
            {"coverType":"poster","url":"/radarr/MediaCover/5/poster.jpg","remoteUrl":"https://image.tmdb.org/t/p/original/p.jpg"},
            {"coverType":"fanart","url":"/radarr/MediaCover/5/fanart.jpg","remoteUrl":"https://image.tmdb.org/t/p/original/f.jpg"}],
          "id":5}]
        """;

    private readonly FakeSeerrHttp _http = new();
    private readonly FakeArrSettings _settings = new();
    private readonly RecordingLogger<ArrClient> _logger = new();

    private ArrClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? ArrClient.DefaultTimeout };

    private void Answer(HttpStatusCode status, string json) =>
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(status, json));

    [Fact]
    public async Task TheSonarrCalendarAsksForTheRangeWithTheSeriesAndTheKey()
    {
        Answer(HttpStatusCode.OK, SonarrCalendar);

        var episodes = await Client().GetEpisodesAsync(From, To, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, seen.Method);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/calendar?start=2026-10-10T02%3A00%3A00Z&end=2026-10-17T14%3A00%3A00Z"
            + "&includeSeries=true&unmonitored=false",
            seen.Uri.OriginalString);
        Assert.Equal("sonarr-key", seen.ApiKey);
        Assert.Equal(ArrClient.HttpClientName, _http.LastClientName);

        var episode = Assert.Single(episodes)!;
        Assert.Equal(12, episode.SeriesId);
        Assert.Equal(1, episode.SeasonNumber);
        Assert.Equal(5, episode.EpisodeNumber);
        Assert.Equal("Episode 5", episode.Title);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 1, 0, 0, TimeSpan.Zero), episode.AirDateUtc);
        Assert.False(episode.HasFile);
        var series = episode.Series!;
        Assert.Equal("American Hostage", series.Title);
        Assert.Equal(462907, series.TvdbId);
        Assert.Equal(239618, series.TmdbId);
        Assert.Equal("tt1234567", series.ImdbId);
        Assert.Equal(
            new[] { "https://artworks.thetvdb.com/b.jpg", "https://artworks.thetvdb.com/p.jpg", "https://artworks.thetvdb.com/f.jpg" },
            series.Images!.Select(image => image!.RemoteUrl));
    }

    [Fact]
    public async Task TheRadarrCalendarAsksOnlyForTheRange()
    {
        Answer(HttpStatusCode.OK, RadarrCalendar);

        var movies = await Client().GetMoviesAsync(From, To, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(
            "https://arr.example/radarr/api/v3/calendar?start=2026-10-10T02%3A00%3A00Z&end=2026-10-17T14%3A00%3A00Z&unmonitored=false",
            seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        var movie = Assert.Single(movies)!;
        Assert.Equal("Hope", movie.Title);
        Assert.Equal(2026, movie.Year);
        Assert.Equal(1058424, movie.TmdbId);
        Assert.Equal(new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.False(movie.HasFile);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", movie.Images![0]!.RemoteUrl);
    }

    [Fact]
    public async Task StatusGivesTheVersionOfEachService()
    {
        _http.Respond = (request, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            request.RequestUri!.AbsolutePath.StartsWith("/sonarr", StringComparison.Ordinal)
                ? """{"appName":"Sonarr","version":"4.0.20.3014"}"""
                : """{"appName":"Radarr","version":"6.4.4.10685"}"""));

        Assert.Equal("4.0.20.3014", (await Client().GetStatusAsync(ArrKind.Sonarr, CancellationToken.None)).Version);
        Assert.Equal("6.4.4.10685", (await Client().GetStatusAsync(ArrKind.Radarr, CancellationToken.None)).Version);
        Assert.Equal("https://arr.example/sonarr/api/v3/system/status", _http.Requests[0].Uri.OriginalString);
        Assert.Equal("sonarr-key", _http.Requests[0].ApiKey);
        Assert.Equal("https://arr.example/radarr/api/v3/system/status", _http.Requests[1].Uri.OriginalString);
        Assert.Equal("radarr-key", _http.Requests[1].ApiKey);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, ArrError.Unauthorized)]
    [InlineData(HttpStatusCode.Forbidden, ArrError.Unauthorized)]
    [InlineData(HttpStatusCode.NotFound, ArrError.Unreachable)]
    [InlineData(HttpStatusCode.Found, ArrError.Unreachable)]
    [InlineData(HttpStatusCode.InternalServerError, ArrError.Unreachable)]
    public async Task RefusedKeysAreUnauthorizedOtherAnswersUnreachable(HttpStatusCode status, ArrError expected)
    {
        Answer(status, "{}");

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        Assert.Equal(expected, error.Error);
    }

    [Fact]
    public async Task NetworkErrorsTimeoutsHtmlAndNullAreUnreachable()
    {
        async Task<ArrError> ErrorOf(ArrClient client) =>
            (await Assert.ThrowsAsync<ArrException>(() => client.GetMoviesAsync(From, To, CancellationToken.None))).Error;

        _http.Respond = (_, _) => throw new HttpRequestException("rete");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "[]");
        };
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client(TimeSpan.FromMilliseconds(50))));

        // Una pagina di login invece del JSON (indirizzo senza l'UrlBase).
        Answer(HttpStatusCode.OK, "<html>");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        Answer(HttpStatusCode.OK, "null");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        _settings.Radarr = new ArrEndpoint("radarr-senza-schema", "radarr-key");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));
    }

    [Fact]
    public async Task NotConfiguredSendsNothing()
    {
        _settings.Sonarr = ArrEndpoint.None;

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        Assert.Equal(ArrError.NotConfigured, error.Error);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task AKeyThatCannotBeAHeaderIsUnreachableAndSendsNothing()
    {
        _settings.Sonarr = new ArrEndpoint("https://arr.example/sonarr", "chiave\r\nsegreta");

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetStatusAsync(ArrKind.Sonarr, CancellationToken.None));

        Assert.Equal(ArrError.Unreachable, error.Error);
        Assert.Empty(_http.Requests);
        Assert.NotEmpty(_logger.Entries);
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("segreta", StringComparison.Ordinal));
    }

    [Fact]
    public async Task TheLogHasThePathButNeverTheKeyOrTheQuery()
    {
        Answer(HttpStatusCode.Unauthorized, "{}");

        await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        var entry = Assert.Single(_logger.Entries);
        Assert.Contains("calendar", entry.Message, StringComparison.Ordinal);
        Assert.Contains("Sonarr", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("sonarr-key", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("2026-10", entry.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ACancelledCallerGetsTheCancellation()
    {
        using var cancel = new CancellationTokenSource();
        _http.Respond = async (_, ct) =>
        {
            await cancel.CancelAsync();
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "[]");
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client().GetEpisodesAsync(From, To, cancel.Token));
    }

    [Fact]
    public async Task NullsInsideTheListsDoNotBreakTheParsing()
    {
        Answer(
            HttpStatusCode.OK,
            """[null,{"seriesId":1,"seasonNumber":1,"episodeNumber":1,"airDateUtc":null,"hasFile":false,"series":{"title":"X","images":null}}]""");

        var episodes = await Client().GetEpisodesAsync(From, To, CancellationToken.None);

        Assert.Equal(2, episodes.Count);
        Assert.Null(episodes[0]);
        Assert.Null(episodes[1]!.AirDateUtc);
        Assert.Null(episodes[1]!.Series!.Images);
    }
}
