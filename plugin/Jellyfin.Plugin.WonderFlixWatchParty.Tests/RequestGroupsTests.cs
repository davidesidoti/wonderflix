using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RequestGroupsTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 14, 12, 0, 0, TimeSpan.Zero);

    private static SeerrRequest Request(
        int status, int mediaStatus, string type = "movie", int ageDays = 5, int downloads = 0, bool partial = false) => new()
    {
        Id = 1,
        Status = status,
        Type = type,
        CreatedAt = Now - TimeSpan.FromDays(ageDays),
        Seasons = partial ? [new SeerrRequestSeason { SeasonNumber = 1, Status = SeerrCodes.RequestCompleted }] : [],
        Media = new SeerrRequestMedia
        {
            TmdbId = 10,
            MediaType = type,
            Status = mediaStatus,
            DownloadStatus = Enumerable.Range(0, downloads).Select(_ => new SeerrDownload { Size = 10, SizeLeft = 5 }).ToList(),
        },
    };

    [Fact]
    public void CompletedWithDeletedMediaIsRemoved()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestCompleted, SeerrCodes.MediaDeleted), null, Now);
        Assert.Equal(RequestStatuses.Removed, status);
        Assert.Equal(RequestGroups.Closed, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void ApprovedWithDeletedMediaIsRemoved() =>
        Assert.Equal(
            RequestStatuses.Removed,
            RequestGroups.StatusOf(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaDeleted), null, Now));

    [Fact]
    public void ApprovedWithDeletedMediaButDownloadingStaysDownloading()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaDeleted, downloads: 1), null, Now);
        Assert.Equal(RequestStatuses.Downloading, status);
        Assert.Equal(RequestGroups.Open, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void DeclinedWithDeletedMediaStaysDeclined() =>
        Assert.Equal(
            RequestStatuses.Declined,
            RequestGroups.StatusOf(Request(SeerrCodes.RequestDeclined, SeerrCodes.MediaDeleted), null, Now));

    [Fact]
    public void ApprovedUnknownMediaAt31DaysIsNotFound()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaUnknown, ageDays: 31), null, Now);
        Assert.Equal(RequestStatuses.NotFound, status);
        Assert.Equal(RequestGroups.Closed, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void ApprovedUnknownMediaAt29DaysIsApproved()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaUnknown, ageDays: 29), null, Now);
        Assert.Equal(RequestStatuses.Approved, status);
        Assert.Equal(RequestGroups.Open, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void ApprovedMovieNotYetReleasedAt31DaysIsAwaitingRelease()
    {
        var request = Request(SeerrCodes.RequestApproved, SeerrCodes.MediaUnknown, ageDays: 31);
        var movie = new MovieDates(null, Now.AddDays(10), null, false);
        var status = RequestGroups.StatusOf(request, movie, Now);
        Assert.Equal(RequestStatuses.AwaitingRelease, status);
        Assert.Equal(RequestGroups.Open, RequestGroups.GroupOf(status));
        Assert.True(RequestGroups.NeedsMovieDates(request, Now));
    }

    [Fact]
    public void ApprovedSeriesAt31DaysIsNotFound()
    {
        var request = Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPending, "tv", ageDays: 31);
        Assert.Equal(RequestStatuses.NotFound, RequestGroups.StatusOf(request, null, Now));
        Assert.False(RequestGroups.NeedsMovieDates(request, Now));
    }

    [Fact]
    public void PartialStaysOpen()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPartial, "tv", partial: true), null, Now);
        Assert.Equal(RequestStatuses.Partial, status);
        Assert.Equal(RequestGroups.Open, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void CompletedWithUnknownMediaIsAvailable()
    {
        var status = RequestGroups.StatusOf(Request(SeerrCodes.RequestCompleted, SeerrCodes.MediaUnknown), null, Now);
        Assert.Equal(RequestStatuses.Available, status);
        Assert.Equal(RequestGroups.Done, RequestGroups.GroupOf(status));
    }

    [Fact]
    public void GroupsOfEveryStatus()
    {
        foreach (var s in new[]
        {
            RequestStatuses.Pending, RequestStatuses.Approved, RequestStatuses.Downloading,
            RequestStatuses.Partial, RequestStatuses.AwaitingRelease,
        })
        {
            Assert.Equal(RequestGroups.Open, RequestGroups.GroupOf(s));
        }

        Assert.Equal(RequestGroups.Done, RequestGroups.GroupOf(RequestStatuses.Available));
        foreach (var s in new[] { RequestStatuses.Declined, RequestStatuses.Failed, RequestStatuses.Removed, RequestStatuses.NotFound })
        {
            Assert.Equal(RequestGroups.Closed, RequestGroups.GroupOf(s));
        }
    }

    [Theory]
    [InlineData("open", true)]
    [InlineData("done", true)]
    [InlineData("closed", true)]
    [InlineData("pending", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    [InlineData("OPEN", false)]
    public void IsGroupAcceptsOnlyTheThreeNames(string? raw, bool expected) =>
        Assert.Equal(expected, RequestGroups.IsGroup(raw));
}
