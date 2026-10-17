using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchFiltersTests
{
    [Fact]
    public void TheAppValuesBecomeFilters()
    {
        Assert.Equal(new MatchFilters(true, false, TimeSpan.FromMinutes(90), "Horror"), MatchFilters.Parse("movies", "90", " Horror "));
        Assert.Equal(new MatchFilters(false, true, TimeSpan.FromMinutes(120), null), MatchFilters.Parse("series", "120", ""));
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse("both", "any", null));
    }

    [Fact]
    public void MissingTypeAndDurationAreBothAndAny()
    {
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse(null, null, "  "));
    }

    [Fact]
    public void UnknownValuesAreRefused()
    {
        Assert.Null(MatchFilters.Parse("films", "any", null));
        Assert.Null(MatchFilters.Parse("both", "60", null));
        Assert.Null(MatchFilters.Parse("both", "any", new string('a', MatchFilters.MaxGenreLength + 1)));
        Assert.NotNull(MatchFilters.Parse("both", "any", new string('a', MatchFilters.MaxGenreLength)));
    }

    [Fact]
    public void TheRatingIsAnyGoodOrBad()
    {
        Assert.Equal(new MatchFilters(true, true, null, null, MinRating: 7), MatchFilters.Parse("both", "any", null, "good"));
        Assert.Equal(new MatchFilters(true, true, null, null, MaxRating: 5), MatchFilters.Parse("both", "any", null, "bad"));
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse("both", "any", null, "any"));
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse("both", "any", null, null));
        Assert.Null(MatchFilters.Parse("both", "any", null, "great"));
    }
}
