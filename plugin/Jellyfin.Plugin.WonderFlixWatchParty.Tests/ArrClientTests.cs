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
    public async Task FindingAMovieAsksRadarrByTmdbId()
    {
        Answer(
            HttpStatusCode.OK,
            """[{"title":"Coco","tmdbId":354912,"inCinemas":"2017-10-27T00:00:00Z","digitalRelease":"2017-11-30T00:00:00Z","physicalRelease":"2018-02-27T00:00:00Z","hasFile":true,"id":1}]""");

        var movies = await Client().FindMoviesAsync(354912, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/radarr/api/v3/movie?tmdbId=354912", seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        var movie = Assert.Single(movies)!;
        Assert.Equal(new DateTimeOffset(2017, 10, 27, 0, 0, 0, TimeSpan.Zero), movie.InCinemas);
        Assert.Equal(new DateTimeOffset(2017, 11, 30, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.Equal(new DateTimeOffset(2018, 2, 27, 0, 0, 0, TimeSpan.Zero), movie.PhysicalRelease);
        Assert.True(movie.HasFile);
    }

    [Fact]
    public async Task TheLookupAsksRadarrForAMovieNotInTheLibrary()
    {
        Answer(
            HttpStatusCode.OK,
            """{"title":"Avatar: Fuoco e cenere","tmdbId":83533,"inCinemas":"2025-12-17T00:00:00Z","digitalRelease":"2026-03-31T00:00:00Z","physicalRelease":"2026-05-19T00:00:00Z"}""");

        var movie = await Client().LookupMovieAsync(83533, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/radarr/api/v3/movie/lookup/tmdb?tmdbId=83533", seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        Assert.Equal(new DateTimeOffset(2025, 12, 17, 0, 0, 0, TimeSpan.Zero), movie.InCinemas);
        Assert.Equal(new DateTimeOffset(2026, 3, 31, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.Equal(new DateTimeOffset(2026, 5, 19, 0, 0, 0, TimeSpan.Zero), movie.PhysicalRelease);
        Assert.False(movie.HasFile);
    }

    [Fact]
    public async Task TheSeriesListHasTheNextAiring()
    {
        Answer(
            HttpStatusCode.OK,
            """[{"title":"Dexter: Resurrection","tvdbId":452595,"tmdbId":259909,"nextAiring":"2026-11-02T01:00:00Z","id":40}]""");

        var series = await Client().GetSeriesAsync(CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/sonarr/api/v3/series", seen.Uri.OriginalString);
        Assert.Equal("sonarr-key", seen.ApiKey);
        var one = Assert.Single(series)!;
        Assert.Equal(40, one.Id);
        Assert.Equal(new DateTimeOffset(2026, 11, 2, 1, 0, 0, TimeSpan.Zero), one.NextAiring);
    }

    [Fact]
    public async Task TheEpisodesOfASeriesAreAskedBySeriesId()
    {
        Answer(
            HttpStatusCode.OK,
            """[{"seriesId":40,"seasonNumber":1,"episodeNumber":4,"airDateUtc":"2026-11-02T01:00:00Z","hasFile":false}]""");

        var episodes = await Client().GetSeriesEpisodesAsync(40, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/sonarr/api/v3/episode?seriesId=40", seen.Uri.OriginalString);
        Assert.Equal("sonarr-key", seen.ApiKey);
        var episode = Assert.Single(episodes)!;
        Assert.Equal(40, episode.SeriesId);
        Assert.Equal(4, episode.EpisodeNumber);
        Assert.Equal(new DateTimeOffset(2026, 11, 2, 1, 0, 0, TimeSpan.Zero), episode.AirDateUtc);
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
    public async Task TheNewReadsLogOnlyThePath()
    {
        Answer(HttpStatusCode.Unauthorized, "{}");
        var client = Client();

        await Assert.ThrowsAsync<ArrException>(() => client.FindMoviesAsync(354912, CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.LookupMovieAsync(354912, CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GetSeriesAsync(CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GetSeriesEpisodesAsync(40, CancellationToken.None));

        Assert.Equal(4, _logger.Entries.Count);
        Assert.Contains("movie", _logger.Entries[0].Message, StringComparison.Ordinal);
        Assert.Contains("movie/lookup/tmdb", _logger.Entries[1].Message, StringComparison.Ordinal);
        Assert.Contains("series", _logger.Entries[2].Message, StringComparison.Ordinal);
        Assert.Contains("episode", _logger.Entries[3].Message, StringComparison.Ordinal);
        Assert.All(_logger.Entries, e =>
        {
            Assert.DoesNotContain("tmdbId=", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("seriesId=", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("radarr-key", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("sonarr-key", e.Message, StringComparison.Ordinal);
        });
    }

    [Fact]
    public async Task SearchingAMovieAsksRadarrForReleases()
    {
        Answer(
            HttpStatusCode.OK,
            """
            [{"guid":"g1","indexerId":3,"indexer":"ItaTorrents (Prowlarr)","title":"Animals (2026) iTA-ENG WEBDL 1080p x264-Dr4gon mkv",
              "size":2900000000,"seeders":7,
              "quality":{"quality":{"id":3,"name":"WEBDL-1080p","resolution":1080}},
              "customFormatScore":150,"rejected":true,
              "rejections":["Existing file on disk has a equal or higher Custom Format score: 150"]}]
            """);

        var releases = await Client().SearchReleasesAsync(ArrKind.Radarr, "movieId=915", CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, seen.Method);
        Assert.Equal("https://arr.example/radarr/api/v3/release?movieId=915", seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        var release = Assert.Single(releases)!;
        Assert.Equal("g1", release.Guid);
        Assert.Equal(3, release.IndexerId);
        Assert.Equal("ItaTorrents (Prowlarr)", release.Indexer);
        Assert.Equal("Animals (2026) iTA-ENG WEBDL 1080p x264-Dr4gon mkv", release.Title);
        Assert.Equal(2900000000L, release.Size);
        Assert.Equal(7, release.Seeders);
        Assert.Equal(3, release.Quality!.Quality!.Id);
        Assert.Equal("WEBDL-1080p", release.Quality.Quality.Name);
        Assert.Equal(1080, release.Quality.Quality.Resolution);
        Assert.Equal(150, release.CustomFormatScore);
        Assert.True(release.Rejected);
        Assert.Equal(
            "Existing file on disk has a equal or higher Custom Format score: 150", Assert.Single(release.Rejections!));
    }

    [Fact]
    public async Task SonarrReleasesKeepTheSeasonPackFields()
    {
        Answer(
            HttpStatusCode.OK,
            """[{"guid":"p1","indexerId":1,"title":"Show S02","size":1,"fullSeason":true,"seasonNumber":2,"episodeNumbers":[1,2,3]}]""");

        var releases = await Client().SearchReleasesAsync(ArrKind.Sonarr, "seriesId=5&seasonNumber=2", CancellationToken.None);

        Assert.Equal("https://arr.example/sonarr/api/v3/release?seriesId=5&seasonNumber=2", Assert.Single(_http.Requests).Uri.OriginalString);
        Assert.Equal("sonarr-key", _http.Requests[0].ApiKey);
        var release = Assert.Single(releases)!;
        Assert.True(release.FullSeason);
        Assert.Equal(2, release.SeasonNumber);
        Assert.Equal(new[] { 1, 2, 3 }, release.EpisodeNumbers);
        Assert.Null(release.Seeders);
    }

    [Fact]
    public async Task GrabbingPostsGuidAndIndexer()
    {
        Answer(HttpStatusCode.OK, "{}");

        await Client().GrabReleaseAsync(ArrKind.Radarr, "g1", 3, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Post, seen.Method);
        Assert.Equal("https://arr.example/radarr/api/v3/release", seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        Assert.Equal("""{"guid":"g1","indexerId":3}""", seen.Body);
    }

    [Fact]
    public async Task AFailedGrabCarriesTheHttpStatus()
    {
        Answer(HttpStatusCode.NotFound, "{}");

        var error = await Assert.ThrowsAsync<ArrException>(
            () => Client().GrabReleaseAsync(ArrKind.Radarr, "g1", 3, CancellationToken.None));

        Assert.Equal(ArrError.Unreachable, error.Error);
        Assert.Equal(404, error.Status);
    }

    [Fact]
    public async Task NetworkErrorsHaveNoHttpStatus()
    {
        _http.Respond = (_, _) => throw new HttpRequestException("rete");

        var error = await Assert.ThrowsAsync<ArrException>(
            () => Client().GrabReleaseAsync(ArrKind.Radarr, "g1", 3, CancellationToken.None));

        Assert.Null(error.Status);
    }

    [Fact]
    public async Task LibraryMoviesCarryTheFieldsTheDownloadsNeed()
    {
        Answer(
            HttpStatusCode.OK,
            """
            [{"id":915,"title":"Animals","year":2026,"tmdbId":9,"runtime":96,"monitored":true,"isAvailable":true,
              "hasFile":true,"qualityProfileId":4,"movieFile":{"id":77,"movieId":915}},
             {"id":916,"title":"No file","hasFile":false,"movieFile":null}]
            """);

        var movies = await Client().GetLibraryMoviesAsync(CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/radarr/api/v3/movie", seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        var movie = movies[0]!;
        Assert.Equal(915, movie.Id);
        Assert.Equal(96, movie.Runtime);
        Assert.True(movie.Monitored);
        Assert.True(movie.IsAvailable);
        Assert.Equal(4, movie.QualityProfileId);
        Assert.Equal(77, movie.MovieFile!.Id);
        Assert.Null(movies[1]!.MovieFile);
    }

    [Fact]
    public async Task MissingEpisodesReadEveryPage()
    {
        _http.Respond = (request, _) =>
        {
            var page = request.RequestUri!.Query.Contains("page=2", StringComparison.Ordinal);
            var records = string.Join(
                ",",
                Enumerable.Range(page ? 251 : 1, page ? 50 : 250).Select(
                    id => $$$"""{"id":{{{id}}},"seriesId":6,"seasonNumber":1,"episodeNumber":{{{id}}},"monitored":true,"hasFile":false,"series":{"title":"S","runtime":24,"qualityProfileId":2,"status":"continuing"}}"""));
            return Task.FromResult(FakeSeerrHttp.Json(HttpStatusCode.OK, $$"""{"page":1,"pageSize":250,"totalRecords":300,"records":[{{records}}]}"""));
        };

        var episodes = await Client().GetMissingEpisodesAsync(CancellationToken.None);

        Assert.Equal(300, episodes.Count);
        Assert.Equal(2, _http.Requests.Count);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/wanted/missing?page=1&pageSize=250&monitored=true&includeSeries=true",
            _http.Requests[0].Uri.OriginalString);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/wanted/missing?page=2&pageSize=250&monitored=true&includeSeries=true",
            _http.Requests[1].Uri.OriginalString);
        Assert.Equal("sonarr-key", _http.Requests[1].ApiKey);
        var last = episodes[299]!;
        Assert.Equal(300, last.Id);
        Assert.True(last.Monitored);
        Assert.Equal(24, last.Series!.Runtime);
        Assert.Equal(2, last.Series.QualityProfileId);
        Assert.Equal("continuing", last.Series.Status);
    }

    [Fact]
    public async Task AnEmptyPageEndsThePagingEvenIfTheTotalIsWrong()
    {
        Answer(HttpStatusCode.OK, """{"totalRecords":999,"records":[]}""");

        var items = await Client().GetQueueAsync(ArrKind.Radarr, CancellationToken.None);

        Assert.Empty(items);
        Assert.Single(_http.Requests);
    }

    [Fact]
    public async Task TheQueueReadsEveryPage()
    {
        _http.Respond = (request, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            request.RequestUri!.Query.Contains("page=2", StringComparison.Ordinal)
                ? """{"totalRecords":251,"records":[{"id":251,"episodeId":9,"seriesId":6,"seasonNumber":2,"downloadId":"D","size":10,"sizeleft":4,"trackedDownloadState":"downloading","status":"paused"}]}"""
                : $$"""{"totalRecords":251,"records":[{{string.Join(",", Enumerable.Range(1, 250).Select(id => $$"""{"id":{{id}},"movieId":5}"""))}}]}"""));

        var items = await Client().GetQueueAsync(ArrKind.Sonarr, CancellationToken.None);

        Assert.Equal(251, items.Count);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/queue?page=1&pageSize=250", _http.Requests[0].Uri.OriginalString);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/queue?page=2&pageSize=250", _http.Requests[1].Uri.OriginalString);
        var last = items[250]!;
        Assert.Equal(251, last.Id);
        Assert.Equal(9, last.EpisodeId);
        Assert.Equal(6, last.SeriesId);
        Assert.Equal(2, last.SeasonNumber);
        Assert.Equal("D", last.DownloadId);
        Assert.Equal(10, last.Size);
        Assert.Equal(4, last.Sizeleft);
        Assert.Equal("downloading", last.TrackedDownloadState);
        Assert.Equal("paused", last.Status);
        Assert.Equal(5, items[0]!.MovieId);
        Assert.Null(items[0]!.EpisodeId);
    }

    [Fact]
    public async Task MovieFilesAreAskedInGroupsOfAHundred()
    {
        _http.Respond = (request, _) =>
        {
            var id = int.Parse(
                System.Text.RegularExpressions.Regex.Match(request.RequestUri!.Query, @"movieFileIds=(\d+)").Groups[1].Value,
                System.Globalization.CultureInfo.InvariantCulture);
            return Task.FromResult(FakeSeerrHttp.Json(
                HttpStatusCode.OK,
                $$$$"""[{"id":{{{{id}}}},"movieId":{{{{id + 1000}}}},"customFormatScore":120,"size":5,"quality":{"quality":{"id":3,"name":"WEBDL-1080p","resolution":1080}}}]"""));
        };

        var files = await Client().GetMovieFilesAsync(Enumerable.Range(1, 150).ToList(), CancellationToken.None);

        Assert.Equal(2, _http.Requests.Count);
        var first = _http.Requests[0].Uri.OriginalString;
        Assert.StartsWith("https://arr.example/radarr/api/v3/moviefile?movieFileIds=1&movieFileIds=2&", first, StringComparison.Ordinal);
        Assert.Equal(100, System.Text.RegularExpressions.Regex.Matches(first, "movieFileIds=").Count);
        Assert.Equal(50, System.Text.RegularExpressions.Regex.Matches(_http.Requests[1].Uri.OriginalString, "movieFileIds=").Count);
        Assert.Equal("radarr-key", _http.Requests[0].ApiKey);
        Assert.Equal(2, files.Count);
        Assert.Equal(1001, files[0]!.MovieId);
        Assert.Equal(120, files[0]!.CustomFormatScore);
        Assert.Equal(5, files[0]!.Size);
        Assert.Equal("WEBDL-1080p", files[0]!.Quality!.Quality!.Name);
    }

    [Fact]
    public async Task NoMovieFileIdsSendNothing()
    {
        var files = await Client().GetMovieFilesAsync([], CancellationToken.None);

        Assert.Empty(files);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task EpisodeFilesAreAskedBySeriesId()
    {
        Answer(
            HttpStatusCode.OK,
            """[{"id":3,"seriesId":6,"seasonNumber":2,"customFormatScore":80,"size":700,"quality":{"quality":{"id":3,"name":"WEBDL-1080p","resolution":1080}}}]""");

        var files = await Client().GetEpisodeFilesAsync(6, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/sonarr/api/v3/episodefile?seriesId=6", seen.Uri.OriginalString);
        Assert.Equal("sonarr-key", seen.ApiKey);
        var file = Assert.Single(files)!;
        Assert.Equal(3, file.Id);
        Assert.Equal(2, file.SeasonNumber);
        Assert.Equal(80, file.CustomFormatScore);
    }

    [Fact]
    public async Task QualityProfilesKeepGroupsAndSingleQualities()
    {
        Answer(
            HttpStatusCode.OK,
            """
            [{"id":4,"name":"Main","items":[
              {"quality":{"id":4,"name":"HDTV-720p","resolution":720},"items":[],"allowed":true},
              {"name":"WEB 1080p","id":1000,"items":[{"quality":{"id":15,"name":"WEBRip-1080p","resolution":1080},"items":[],"allowed":true},
                                                     {"quality":{"id":3,"name":"WEBDL-1080p","resolution":1080},"items":[],"allowed":true}],"allowed":true},
              {"quality":{"id":1,"name":"SDTV","resolution":480},"items":[],"allowed":false}]}]
            """);

        var profiles = await Client().GetQualityProfilesAsync(ArrKind.Radarr, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://arr.example/radarr/api/v3/qualityprofile", seen.Uri.OriginalString);
        var profile = Assert.Single(profiles)!;
        Assert.Equal(4, profile.Id);
        Assert.Equal("Main", profile.Name);
        Assert.Equal(3, profile.Items!.Count);
        Assert.Equal("HDTV-720p", profile.Items[0]!.Quality!.Name);
        Assert.Null(profile.Items[0]!.Name);
        Assert.True(profile.Items[0]!.Allowed);
        Assert.Equal("WEB 1080p", profile.Items[1]!.Name);
        Assert.Equal(2, profile.Items[1]!.Items!.Count);
        Assert.False(profile.Items[2]!.Allowed);
    }

    [Fact]
    public async Task IndexersGiveTheirPriority()
    {
        Answer(HttpStatusCode.OK, """[{"id":3,"priority":25,"name":"ItaTorrents"}]""");

        var indexers = await Client().GetIndexersAsync(ArrKind.Sonarr, CancellationToken.None);

        Assert.Equal("https://arr.example/sonarr/api/v3/indexer", Assert.Single(_http.Requests).Uri.OriginalString);
        var indexer = Assert.Single(indexers)!;
        Assert.Equal(3, indexer.Id);
        Assert.Equal(25, indexer.Priority);
    }

    [Fact]
    public async Task RemovingFromTheQueueCanBlocklist()
    {
        Answer(HttpStatusCode.OK, "{}");

        await Client().RemoveFromQueueAsync(ArrKind.Radarr, 77, blocklist: true, CancellationToken.None);
        await Client().RemoveFromQueueAsync(ArrKind.Sonarr, 5, blocklist: false, CancellationToken.None);

        Assert.Equal(HttpMethod.Delete, _http.Requests[0].Method);
        Assert.Equal(
            "https://arr.example/radarr/api/v3/queue/77?removeFromClient=true&blocklist=true",
            _http.Requests[0].Uri.OriginalString);
        Assert.Equal("radarr-key", _http.Requests[0].ApiKey);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/queue/5?removeFromClient=true&blocklist=false",
            _http.Requests[1].Uri.OriginalString);
    }

    [Fact]
    public async Task AnEmptyBodyIsFineWhenNothingIsRead()
    {
        _http.Respond = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));

        await Client().RemoveFromQueueAsync(ArrKind.Radarr, 1, blocklist: false, CancellationToken.None);
    }

    [Fact]
    public async Task ASlowSearchUsesTheSearchTimeout()
    {
        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(200, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "[]");
        };
        var client = Client(TimeSpan.FromMilliseconds(50));

        var releases = await client.SearchReleasesAsync(ArrKind.Radarr, "movieId=1", CancellationToken.None);

        Assert.Empty(releases);
        var error = await Assert.ThrowsAsync<ArrException>(() => client.GetLibraryMoviesAsync(CancellationToken.None));
        Assert.Equal(ArrError.Unreachable, error.Error);
        Assert.Equal(TimeSpan.FromMinutes(2), ArrClient.SearchTimeout);
    }

    [Fact]
    public async Task TheNewCallsLogTheMethodAndThePathButNeverTheQueryOrTheRelease()
    {
        Answer(HttpStatusCode.Unauthorized, "{}");
        var client = Client();

        await Assert.ThrowsAsync<ArrException>(() => client.SearchReleasesAsync(ArrKind.Radarr, "movieId=915", CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GrabReleaseAsync(ArrKind.Radarr, "secret-guid", 3, CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GetMissingEpisodesAsync(CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GetQueueAsync(ArrKind.Radarr, CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.RemoveFromQueueAsync(ArrKind.Radarr, 77, true, CancellationToken.None));
        await Assert.ThrowsAsync<ArrException>(() => client.GetMovieFilesAsync([1, 2], CancellationToken.None));

        Assert.Equal(6, _logger.Entries.Count);
        Assert.Contains("GET release", _logger.Entries[0].Message, StringComparison.Ordinal);
        Assert.Contains("POST release", _logger.Entries[1].Message, StringComparison.Ordinal);
        Assert.Contains("wanted/missing", _logger.Entries[2].Message, StringComparison.Ordinal);
        Assert.Contains("queue", _logger.Entries[3].Message, StringComparison.Ordinal);
        Assert.Contains("DELETE queue/77", _logger.Entries[4].Message, StringComparison.Ordinal);
        Assert.Contains("moviefile", _logger.Entries[5].Message, StringComparison.Ordinal);
        Assert.All(_logger.Entries, e =>
        {
            Assert.DoesNotContain("movieId=", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("movieFileIds", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("page=", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("secret-guid", e.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("radarr-key", e.Message, StringComparison.Ordinal);
        });
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
