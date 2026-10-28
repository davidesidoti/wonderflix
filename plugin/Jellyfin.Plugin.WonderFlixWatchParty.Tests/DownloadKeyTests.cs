using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class DownloadKeyTests
{
    [Theory]
    [InlineData("Movie", 12, 0, "movie:12")]
    [InlineData("Episode", 34, 0, "episode:34")]
    [InlineData("Season", 5, 2, "season:5:2")]
    [InlineData("Season", 5, 0, "season:5:0")]
    public void RoundTrips(string kind, int id, int season, string wire)
    {
        var key = new DownloadKey(kind, id, season);
        Assert.Equal(wire, key.ToString());
        Assert.True(DownloadKey.TryParse(wire, out var parsed));
        Assert.Equal(key, parsed);
    }

    [Theory]
    [InlineData("")]
    [InlineData("movie:")]
    [InlineData("movie:-1")]
    [InlineData("movie:0")]
    [InlineData("film:3")]
    [InlineData("season:5")]
    [InlineData("season:5:-1")]
    [InlineData("movie:1:2")]
    [InlineData("Movie:1")]
    [InlineData(null)]
    public void RejectsGarbage(string? raw) => Assert.False(DownloadKey.TryParse(raw, out _));
}
