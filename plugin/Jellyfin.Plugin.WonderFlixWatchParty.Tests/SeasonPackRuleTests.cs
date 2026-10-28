using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeasonPackRuleTests
{
    private const long Gb = 1_000_000_000;

    private static readonly int[] Missing = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    private static readonly RuleInput PerEpisode = new(45, false, DownloadRule.DefaultMinGbPerHour, 50, new Dictionary<int, int>());

    private static ArrRelease Pack(double gb, params string[] rejections) => new()
    {
        Guid = "pack",
        Size = (long)(gb * Gb),
        CustomFormatScore = 100,
        FullSeason = true,
        Rejections = rejections.ToList(),
    };

    private static ArrRelease Single(int episode, double gb = 1) => new()
    {
        Guid = "ep" + episode,
        Size = (long)(gb * Gb),
        CustomFormatScore = 100,
        EpisodeNumbers = [episode],
    };

    private static IEnumerable<ArrRelease> Singles(int count) => Missing.Take(count).Select(e => Single(e));

    [Fact]
    public void ALightPackWins() =>
        Assert.Equal("pack", SeasonPackRule.ChoosePack(Singles(10).Append(Pack(11)), Missing, PerEpisode)?.Guid);

    [Fact]
    public void AHeavyPackLoses() =>
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10).Append(Pack(14)), Missing, PerEpisode));

    [Fact]
    public void AMissingSingleTakesThePack() =>
        Assert.Equal("pack", SeasonPackRule.ChoosePack(Singles(9).Append(Pack(14)), Missing, PerEpisode)?.Guid);

    [Fact]
    public void NothingValidSplits()
    {
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10).Append(Pack(11, "Unknown series")), Missing, PerEpisode));
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10), Missing, PerEpisode));
    }
}
