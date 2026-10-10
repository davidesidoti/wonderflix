using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeRowIdsTests
{
    [Fact]
    public void TheKnownRowsAreTheTenOfTheSpecInTheDefaultOrder()
    {
        Assert.Equal(
            new[]
            {
                "resume", "nextUp", "requests", "latestMovies", "latestSeries",
                "becauseYouWatched", "continueSaga", "upcomingSeries", "upcomingMovies", "myList",
            },
            HomeRowIds.Known);
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
}
