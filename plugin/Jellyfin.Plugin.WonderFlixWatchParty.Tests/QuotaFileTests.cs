using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class QuotaFileTests
{
    [Fact]
    public void TheRealQuotaLineIsRead()
    {
        var text = "Disk quotas for user hashvps (uid 1130): \n     Filesystem   blocks   quota   limit   grace   files   quota   limit   grace\n      /dev/sds1 11625889424  11718885376 11718885376          576640       0       0\n";

        var quota = QuotaFile.Parse(text);

        Assert.NotNull(quota);
        Assert.Equal(11625889424L * 1024, quota.UsedBytes);
        Assert.Equal(11718885376L * 1024, quota.LimitBytes);
    }

    [Fact]
    public void AnOverQuotaStarIsIgnored()
    {
        var quota = QuotaFile.Parse("/dev/sds1 11718885377* 11718885376 11718885376 6d 576640 0 0");

        Assert.NotNull(quota);
        Assert.Equal(11718885377L * 1024, quota.UsedBytes);
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("ciao")]
    public void GarbageIsNull(string? text) => Assert.Null(QuotaFile.Parse(text));
}
