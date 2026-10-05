using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrMappingTests
{
    private static SeerrRequest Request(int status, int mediaStatus = SeerrCodes.MediaUnknown, params int[] seasons) => new()
    {
        Status = status,
        Seasons = seasons.Select(n => new SeerrRequestSeason { SeasonNumber = n }).ToList(),
        Media = new SeerrRequestMedia { Status = mediaStatus },
    };

    [Theory]
    [InlineData("2024-02-27", 2024)]
    [InlineData("2026", 2026)]
    [InlineData("", null)]
    [InlineData(null, null)]
    [InlineData("abcd-01-01", null)]
    public void YearFromASeerrDate(string? date, int? year) => Assert.Equal(year, SeerrMapping.Year(date));

    [Theory]
    [InlineData("EE39BEF06F503DD0E9DBD20593DF417F", "ee39bef06f503dd0e9dbd20593df417f")]
    [InlineData("ee39bef0-6f50-3dd0-e9db-d20593df417f", "ee39bef06f503dd0e9dbd20593df417f")]
    [InlineData("00000000000000000000000000000000", null)]
    [InlineData("", null)]
    [InlineData(null, null)]
    public void JellyfinIdsInNFormat(string? raw, string? id) => Assert.Equal(id, SeerrMapping.JellyfinId(raw));

    [Theory]
    [InlineData(null, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaUnknown, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaPending, TitleStatuses.Pending)]
    [InlineData(SeerrCodes.MediaProcessing, TitleStatuses.Processing)]
    [InlineData(SeerrCodes.MediaPartial, TitleStatuses.Partial)]
    [InlineData(SeerrCodes.MediaAvailable, TitleStatuses.Available)]
    [InlineData(SeerrCodes.MediaBlocklisted, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaDeleted, TitleStatuses.None)]
    public void TitleStatusFromSeerr(int? status, string expected) =>
        Assert.Equal(expected, SeerrMapping.TitleStatus(status));

    [Fact]
    public void SeasonsWithoutSpecialsAndWithTheirStatus()
    {
        var tv = new SeerrTv
        {
            Seasons =
            [
                new() { SeasonNumber = 3, EpisodeCount = 10 },
                new() { SeasonNumber = 0, EpisodeCount = 2 },
                new() { SeasonNumber = 1, EpisodeCount = 8 },
                new() { SeasonNumber = 2, EpisodeCount = 9 },
                new() { SeasonNumber = 4, EpisodeCount = 6 },
                new() { SeasonNumber = 5, EpisodeCount = 6 },
            ],
            MediaInfo = new SeerrMediaInfo
            {
                Status = SeerrCodes.MediaPartial,
                Seasons = [new() { SeasonNumber = 1, Status = SeerrCodes.MediaAvailable }],
                Requests =
                [
                    Request(SeerrCodes.RequestPending, SeerrCodes.MediaPartial, 2),
                    Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPartial, 3),
                    Request(SeerrCodes.RequestDeclined, SeerrCodes.MediaPartial, 4),
                ],
            },
        };

        var seasons = SeerrMapping.Seasons(tv);

        Assert.Equal(new[] { 1, 2, 3, 4, 5 }, seasons.Select(s => s.SeasonNumber));
        Assert.Equal(8, seasons[0].EpisodeCount);
        Assert.Equal(
            new[] { TitleStatuses.Available, TitleStatuses.Pending, TitleStatuses.Processing, TitleStatuses.None, TitleStatuses.None },
            seasons.Select(s => s.Status));
    }

    [Fact]
    public void SeasonsOfASeriesSeerrDoesNotKnowAreAllRequestable()
    {
        var tv = new SeerrTv { Seasons = [new() { SeasonNumber = 1, EpisodeCount = 6 }] };

        Assert.Equal(TitleStatuses.None, Assert.Single(SeerrMapping.Seasons(tv)).Status);
    }

    [Fact]
    public void RequestStatusInTheOrderOfThePlan()
    {
        Assert.Equal(RequestStatuses.Declined, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestDeclined, SeerrCodes.MediaAvailable)));
        Assert.Equal(RequestStatuses.Failed, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestFailed)));
        Assert.Equal(RequestStatuses.Pending, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestPending, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Available, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestCompleted, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Available, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaAvailable)));
        Assert.Equal(RequestStatuses.Partial, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Approved, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved)));

        var downloading = Request(SeerrCodes.RequestApproved, SeerrCodes.MediaProcessing);
        downloading.Media!.DownloadStatus.Add(new SeerrDownload { Size = 1000, SizeLeft = 250 });
        Assert.Equal(RequestStatuses.Downloading, SeerrMapping.RequestStatus(downloading));
    }

    [Fact]
    public void ProgressOfTheFirstDownload()
    {
        Assert.Null(SeerrMapping.Progress([]));
        Assert.Null(SeerrMapping.Progress([new SeerrDownload { Size = 0, SizeLeft = 0 }]));
        Assert.Equal(0.75, SeerrMapping.Progress([new SeerrDownload { Size = 1000, SizeLeft = 250 }]));
        Assert.Equal(0.0, SeerrMapping.Progress([new SeerrDownload { Size = 1000, SizeLeft = 2000 }]));
    }

    [Fact]
    public void TrailerFirstThenTeaserOnlyFromYouTubeOverHttp()
    {
        Assert.Equal(
            "https://www.youtube.com/watch?v=t",
            SeerrMapping.TrailerUrl(
            [
                new() { Type = "Teaser", Site = "YouTube", Url = "https://www.youtube.com/watch?v=s" },
                new() { Type = "Trailer", Site = "Vimeo", Url = "https://vimeo.com/1" },
                new() { Type = "Trailer", Site = "YouTube", Url = "https://www.youtube.com/watch?v=t" },
            ]));
        Assert.Equal(
            "https://www.youtube.com/watch?v=s",
            SeerrMapping.TrailerUrl([new() { Type = "Teaser", Site = "YouTube", Url = "https://www.youtube.com/watch?v=s" }]));
        Assert.Null(SeerrMapping.TrailerUrl([new() { Type = "Trailer", Site = "YouTube", Url = "javascript:alert(1)" }]));
        Assert.Null(SeerrMapping.TrailerUrl([]));
    }

    [Fact]
    public void RequestedAndRequestedByMeCountOnlyOpenRequests()
    {
        var info = new SeerrMediaInfo
        {
            Requests =
            [
                new() { Status = SeerrCodes.RequestDeclined, RequestedBy = new() { Id = 5 } },
                new() { Status = SeerrCodes.RequestApproved, RequestedBy = new() { Id = 7 } },
            ],
        };

        Assert.True(SeerrMapping.Requested(info));
        Assert.True(SeerrMapping.RequestedBy(info, 7));
        Assert.False(SeerrMapping.RequestedBy(info, 5));
        Assert.False(SeerrMapping.RequestedBy(info, null));
        Assert.False(SeerrMapping.Requested(null));
    }
}
