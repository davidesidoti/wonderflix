using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeRowIdsTests
{
    [Fact]
    public void TheKnownRowsAreTheElevenOfTheSpecsInTheDefaultOrder()
    {
        Assert.Equal(
            new[]
            {
                "resume", "nextUp", "recommended", "requests", "latestMovies", "latestSeries",
                "becauseYouWatched", "continueSaga", "upcomingSeries", "upcomingMovies", "myList",
            },
            HomeRowIds.Known);
        Assert.Equal(new[] { "recommended" }, HomeRowIds.AddedLater);
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
        // Dopo nextUp, anche se l'admin l'ha spostata.
        var change = HomeRowIds.WithLaterRows(["myList", "nextUp", "resume"], []);
        Assert.Equal(new[] { "myList", "nextUp", "resume", "recommended" }, change!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, change.Value.Seen);

        Assert.Equal(new[] { "nextUp", "recommended", "myList" }, HomeRowIds.WithLaterRows(["nextUp", "myList"], [])!.Value.Rows);

        // Né resume né nextUp accese: in testa.
        Assert.Equal(new[] { "recommended", "myList" }, HomeRowIds.WithLaterRows(["myList"], [])!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, HomeRowIds.WithLaterRows([], [])!.Value.Rows);

        // Già accesa: resta dov'è, si segna vista.
        var on = HomeRowIds.WithLaterRows(["recommended", "resume"], []);
        Assert.Equal(new[] { "recommended", "resume" }, on!.Value.Rows);

        // Già vista: niente da fare, anche se l'admin l'ha spenta.
        Assert.Null(HomeRowIds.WithLaterRows(["resume"], ["recommended"]));
    }

    [Fact]
    public void ANeverSetHomeOnlyMarksTheLaterRowsSeen()
    {
        var change = HomeRowIds.WithLaterRows(null, []);
        Assert.Null(change!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, change.Value.Seen);
    }

    [Fact]
    public void SeenRowsAreReadFromTheStoredText()
    {
        Assert.Empty(HomeRowIds.ParseSeen(null));
        Assert.Empty(HomeRowIds.ParseSeen(string.Empty));
        Assert.Equal(new[] { "recommended", "x" }, HomeRowIds.ParseSeen(" recommended,,x,recommended"));
    }
}
