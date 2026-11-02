using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadActionsTests
{
    private static DownloadEntry Entry(string state, string? reason, string kind = DownloadKinds.Movie, DownloadSummary? summary = null, string? downloadId = null) =>
        new() { Kind = kind, State = state, Reason = reason, Summary = summary, DownloadId = downloadId };

    private static DownloadEntry NeedsYou(string reason, string kind = DownloadKinds.Movie, DownloadSummary? summary = null, string? downloadId = null) =>
        Entry(DownloadStates.NeedsYou, reason, kind, summary, downloadId);

    [Fact]
    public void BelowMinScoreMovieRecommendsGrabBest() =>
        Assert.Equal(["GrabBest", "Pick", "SearchNow"], DownloadActions.For(NeedsYou(DownloadReasons.BelowMinScore)));

    [Fact]
    public void BelowMinScoreSeasonHasNoGrabBest() =>
        Assert.Equal(["Pick", "SearchNow"], DownloadActions.For(NeedsYou(DownloadReasons.BelowMinScore, DownloadKinds.Season)));

    [Fact]
    public void NothingFoundWithAStopgapRecommendsGrabBest() =>
        Assert.Equal(
            ["GrabBest", "Pick", "SearchNow", "Snooze"],
            DownloadActions.For(NeedsYou(DownloadReasons.NothingFound, DownloadKinds.Episode, new DownloadSummary { Found = 3, StopgapAvailable = true })));

    [Fact]
    public void NothingFoundWithReleasesButNoStopgapOffersPick() =>
        Assert.Equal(["Pick", "SearchNow", "Snooze"], DownloadActions.For(NeedsYou(DownloadReasons.NothingFound, summary: new DownloadSummary { Found = 3 })));

    [Fact]
    public void NothingFoundWithNoReleasesOffersSnoozeFirst() =>
        Assert.Equal(["Snooze", "SearchNow"], DownloadActions.For(NeedsYou(DownloadReasons.NothingFound, summary: new DownloadSummary())));

    [Fact]
    public void NothingFoundWithoutSummaryIsAnOldEntry() =>
        Assert.Equal(["Pick", "SearchNow", "Snooze"], DownloadActions.For(NeedsYou(DownloadReasons.NothingFound)));

    [Fact]
    public void ImportBlockedWithDownloadIdCanImportOrDiscard() =>
        Assert.Equal(["Import", "Discard"], DownloadActions.For(NeedsYou(DownloadReasons.ImportBlocked, downloadId: "abc")));

    [Theory]
    [InlineData("Not a Custom Format upgrade for existing episode file(s)")]
    [InlineData("Not an Upgrade for existing movie file")]
    public void ImportBlockedThatIsNotAnUpgradeRecommendsDiscard(string message)
    {
        var entry = NeedsYou(DownloadReasons.ImportBlocked, downloadId: "abc");
        entry.BlockedMessage = message;
        Assert.Equal(["Discard", "Import"], DownloadActions.For(entry));
    }

    [Fact]
    public void ImportBlockedForAnotherReasonRecommendsImport()
    {
        var entry = NeedsYou(DownloadReasons.ImportBlocked, downloadId: "abc");
        entry.BlockedMessage = "Series title mismatch";
        Assert.Equal(["Import", "Discard"], DownloadActions.For(entry));
    }

    [Fact]
    public void ImportBlockedWithoutDownloadIdCanOnlyDiscard() =>
        Assert.Equal(["Discard"], DownloadActions.For(NeedsYou(DownloadReasons.ImportBlocked)));

    [Fact]
    public void GrabRefusedOffersPickAndSearch() =>
        Assert.Equal(["Pick", "SearchNow"], DownloadActions.For(NeedsYou(DownloadReasons.GrabRefused)));

    [Fact]
    public void DownloadingWhileFetchingMetadataCanBeDiscarded() =>
        Assert.Equal(["Pick", "SearchNow", "Discard"], DownloadActions.For(new DownloadEntry { State = DownloadStates.Downloading, MetadataSince = T0 }));

    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(DownloadStates.Waiting)]
    [InlineData(DownloadStates.Downloading)]
    [InlineData(DownloadStates.UpgradeWatch)]
    public void OtherStatesOfferPickAndSearch(string state) =>
        Assert.Equal(["Pick", "SearchNow"], DownloadActions.For(Entry(state, null)));
}
