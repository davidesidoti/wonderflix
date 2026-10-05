using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrJsonTests
{
    [Fact]
    public void ReadsASearchPage()
    {
        const string json = """
            {"page":1,"totalPages":65,"results":[
              {"id":438631,"mediaType":"movie","title":"Dune","releaseDate":"2021-09-15","posterPath":"/a.jpg",
               "mediaInfo":{"id":155,"tmdbId":438631,"status":5,"jellyfinMediaId":"ee39bef06f503dd0e9dbd20593df417f"}},
              {"id":90228,"mediaType":"tv","name":"Dune: Prophecy","firstAirDate":"2024-11-17","posterPath":null,"mediaInfo":null},
              {"id":1,"mediaType":"person","name":"Timothée"}]}
            """;

        var page = JsonSerializer.Deserialize<SeerrSearchPage>(json, SeerrJson.Options)!;

        Assert.Equal(3, page.Results.Count);
        Assert.Equal("Dune", page.Results[0].Title);
        Assert.Equal("2021-09-15", page.Results[0].ReleaseDate);
        Assert.Equal(5, page.Results[0].MediaInfo!.Status);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", page.Results[0].MediaInfo!.JellyfinMediaId);
        Assert.Equal("tv", page.Results[1].MediaType);
        Assert.Equal("Dune: Prophecy", page.Results[1].Name);
        Assert.Null(page.Results[1].MediaInfo);
    }

    [Fact]
    public void ReadsASeriesWithSeasonsRequestsAndVideos()
    {
        const string json = """
            {"id":250203,"name":"Brothers","firstAirDate":"2026-09-22","overview":"Due fratelli",
             "genres":[{"id":35,"name":"Commedia"}],"posterPath":"/p.jpg","backdropPath":"/b.jpg",
             "relatedVideos":[{"type":"Trailer","site":"YouTube","key":"x","url":"https://www.youtube.com/watch?v=x"}],
             "seasons":[{"seasonNumber":0,"episodeCount":2},{"seasonNumber":1,"episodeCount":8}],
             "mediaInfo":{"status":4,"jellyfinMediaId":"6d1c8ea33a794f76fdbe92a216959073",
               "seasons":[{"seasonNumber":1,"status":4}],
               "requests":[{"id":432,"status":2,"seasons":[{"seasonNumber":1,"status":2}],
                            "requestedBy":{"id":24,"displayName":"sronweb"}}],
               "downloadStatus":[]}}
            """;

        var tv = JsonSerializer.Deserialize<SeerrTv>(json, SeerrJson.Options)!;

        Assert.Equal("Brothers", tv.Name);
        Assert.Equal("Commedia", Assert.Single(tv.Genres).Name);
        Assert.Equal("https://www.youtube.com/watch?v=x", Assert.Single(tv.RelatedVideos).Url);
        Assert.Equal(new[] { 0, 1 }, tv.Seasons.Select(s => s.SeasonNumber));
        Assert.Equal(8, tv.Seasons[1].EpisodeCount);
        Assert.Equal(4, Assert.Single(tv.MediaInfo!.Seasons).Status);
        var request = Assert.Single(tv.MediaInfo.Requests);
        Assert.Equal(24, request.RequestedBy!.Id);
        Assert.Equal(1, Assert.Single(request.Seasons).SeasonNumber);
    }

    [Fact]
    public void ReadsARequestPage()
    {
        const string json = """
            {"pageInfo":{"pages":138,"pageSize":3,"results":413,"page":1},"results":[
              {"id":434,"status":2,"type":"tv","is4k":false,"createdAt":"2026-10-03T20:31:16.000Z",
               "seasons":[{"seasonNumber":14,"status":2}],
               "requestedBy":{"id":24,"displayName":"sronweb","jellyfinUserId":"150fe35a657b4c5ea4fd644c4c5152b5"},
               "media":{"tmdbId":59941,"mediaType":"tv","status":1,"jellyfinMediaId":null,
                        "downloadStatus":[{"size":1000,"sizeLeft":250,"status":"downloading"}]}}]}
            """;

        var page = JsonSerializer.Deserialize<SeerrPage<SeerrRequest>>(json, SeerrJson.Options)!;

        Assert.Equal(413, page.PageInfo!.Results);
        var request = Assert.Single(page.Results);
        Assert.Equal(434, request.Id);
        Assert.Equal(new DateTimeOffset(2026, 10, 3, 20, 31, 16, TimeSpan.Zero), request.CreatedAt);
        Assert.Equal("sronweb", request.RequestedBy!.DisplayName);
        Assert.Equal(59941, request.Media!.TmdbId);
        Assert.Equal(250, Assert.Single(request.Media.DownloadStatus).SizeLeft);
    }

    [Fact]
    public void WritesANewRequestInCamelCaseWithoutSeasonsForAMovie()
    {
        Assert.Equal(
            """{"mediaType":"movie","mediaId":5}""",
            JsonSerializer.Serialize(new SeerrCreateRequest { MediaType = "movie", MediaId = 5 }, SeerrJson.Options));
        Assert.Equal(
            """{"mediaType":"tv","mediaId":7,"seasons":[1,2]}""",
            JsonSerializer.Serialize(
                new SeerrCreateRequest { MediaType = "tv", MediaId = 7, Seasons = [1, 2] }, SeerrJson.Options));
    }

    [Fact]
    public void ReadsTheWebhookPayload()
    {
        const string json = """
            {"secret":"s","notification_type":"MEDIA_AVAILABLE","subject":"Dune (2021)","request_id":"53",
             "media_type":"movie","media_tmdbid":"438631","media_jellyfinMediaId":"ee39bef06f503dd0e9dbd20593df417f",
             "requestedBy_jellyfinUserId":"150fe35a657b4c5ea4fd644c4c5152b5","requestedBy_username":"sronweb",
             "extra":[{"name":"Requested Seasons","value":"1, 2"}]}
            """;

        var payload = JsonSerializer.Deserialize<SeerrWebhookPayload>(json, SeerrJson.Options)!;

        Assert.Equal("s", payload.Secret);
        Assert.Equal("MEDIA_AVAILABLE", payload.NotificationType);
        Assert.Equal("Dune (2021)", payload.Subject);
        Assert.Equal("53", payload.RequestId);
        Assert.Equal("movie", payload.MediaType);
        Assert.Equal("438631", payload.MediaTmdbId);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", payload.MediaJellyfinMediaId);
        Assert.Equal("150fe35a657b4c5ea4fd644c4c5152b5", payload.RequestedByJellyfinUserId);
        Assert.Equal("sronweb", payload.RequestedByUsername);
        Assert.Equal("1, 2", Assert.Single(payload.Extra!).Value);
    }
}
