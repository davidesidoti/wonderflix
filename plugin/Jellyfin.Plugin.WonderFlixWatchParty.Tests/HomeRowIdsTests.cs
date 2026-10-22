using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeRowIdsTests
{
    [Fact]
    public void TheKnownRowsAreTheTwelveOfTheSpecsInTheDefaultOrder()
    {
        Assert.Equal(
            new[]
            {
                "resume", "nextUp", "recommended", "friendsWatched", "requests", "latestMovies", "latestSeries",
                "becauseYouWatched", "continueSaga", "upcomingSeries", "upcomingMovies", "myList",
            },
            HomeRowIds.Known);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, HomeRowIds.AddedLater);
    }

    [Fact]
    public void NormalizeKeepsTheOrderAndDropsUnknownDuplicatesNullsAndOtherCases()
    {
        Assert.Equal(
            new[] { "myList", "resume", "upcomingSeries" },
            HomeRowIds.Normalize(["myList", "bogus", "resume", null, "myList", "Resume", " nextUp", "upcomingSeries"]));
        Assert.Empty(HomeRowIds.Normalize([]));
    }

    [Fact]
    public void StoredTextKeepsNullApartFromEmpty()
    {
        Assert.Null(HomeRowIds.Parse(null));
        Assert.Empty(HomeRowIds.Parse(string.Empty)!);
        Assert.Equal(new[] { "nextUp", "resume" }, HomeRowIds.Parse("nextUp, resume,,bogus,nextUp"));
        Assert.Equal("nextUp,resume", HomeRowIds.Serialize(["nextUp", "resume"]));
        Assert.Equal(string.Empty, HomeRowIds.Serialize([]));
    }

    [Fact]
    public void LaterRowsGoAfterTheirLastEarlierRowOnce()
    {
        // Dopo nextUp, anche se l'admin l'ha spostata; friendsWatched subito dopo recommended.
        var change = HomeRowIds.WithLaterRows(["myList", "nextUp", "resume"], []);
        Assert.Equal(new[] { "myList", "nextUp", "resume", "recommended", "friendsWatched" }, change!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, change.Value.Seen);

        Assert.Equal(
            new[] { "nextUp", "recommended", "friendsWatched", "myList" },
            HomeRowIds.WithLaterRows(["nextUp", "myList"], [])!.Value.Rows);

        // Né resume né nextUp accese: in testa.
        Assert.Equal(new[] { "recommended", "friendsWatched", "myList" }, HomeRowIds.WithLaterRows(["myList"], [])!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, HomeRowIds.WithLaterRows([], [])!.Value.Rows);

        // Già accesa: resta dov'è; l'altra va dopo l'ultima che la precede.
        var on = HomeRowIds.WithLaterRows(["recommended", "resume"], []);
        Assert.Equal(new[] { "recommended", "resume", "friendsWatched" }, on!.Value.Rows);

        // La Home della 1.8.0, con recommended già vista (anche se spenta): arriva solo friendsWatched.
        var from18 = HomeRowIds.WithLaterRows(["resume"], ["recommended"]);
        Assert.Equal(new[] { "resume", "friendsWatched" }, from18!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, from18.Value.Seen);

        // Tutte già viste: niente da fare.
        Assert.Null(HomeRowIds.WithLaterRows(["resume"], ["recommended", "friendsWatched"]));
    }

    [Fact]
    public void ANeverSetHomeOnlyMarksTheLaterRowsSeen()
    {
        var change = HomeRowIds.WithLaterRows(null, []);
        Assert.Null(change!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, change.Value.Seen);
    }

    [Fact]
    public void SeenRowsAreReadFromTheStoredText()
    {
        Assert.Empty(HomeRowIds.ParseSeen(null));
        Assert.Empty(HomeRowIds.ParseSeen(string.Empty));
        Assert.Equal(new[] { "recommended", "x" }, HomeRowIds.ParseSeen(" recommended,,x,recommended"));
    }
}
