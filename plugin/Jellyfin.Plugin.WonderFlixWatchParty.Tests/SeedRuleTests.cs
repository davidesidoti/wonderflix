using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeedRuleTests
{
    private static readonly SeedSettings Settings = new(["itatorrents.xyz", "shareisland.org"], 10.0, 30);

    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-30T12:00:00Z");

    private static TorrentFacts Torrent(string host, double ratio, long seedingSeconds, double progress = 1) =>
        new("abc", "name", host, 1_000, progress, ratio, seedingSeconds);

    [Fact]
    public void AnUnprotectedTorrentGoesNow()
    {
        var verdict = SeedRule.Check(Torrent("tracker.example.org", 0.1, 0), Settings, Now);

        Assert.True(verdict.CanRemoveNow);
        Assert.Null(verdict.ExpectedAt);
    }

    [Fact]
    public void AProtectedTorrentWaitsForThirtyDays()
    {
        var verdict = SeedRule.Check(Torrent("itatorrents.xyz", 3, 10 * 86_400), Settings, Now);

        Assert.False(verdict.CanRemoveNow);
        Assert.Equal(DateTimeOffset.Parse("2026-11-19T12:00:00Z"), verdict.ExpectedAt);
    }

    [Fact]
    public void RatioTenFreesAProtectedTorrent()
    {
        var verdict = SeedRule.Check(Torrent("shareisland.org", 10, 86_400), Settings, Now);

        Assert.True(verdict.CanRemoveNow);
    }

    [Fact]
    public void ThirtyDaysFreeAProtectedTorrent()
    {
        var verdict = SeedRule.Check(Torrent("shareisland.org", 0.5, 2_592_000), Settings, Now);

        Assert.True(verdict.CanRemoveNow);
    }

    [Fact]
    public void ASubdomainIsProtected()
    {
        Assert.True(SeedRule.IsProtected("tracker.itatorrents.xyz", Settings.ProtectedDomains));
        Assert.True(SeedRule.IsProtected("ITATORRENTS.xyz", Settings.ProtectedDomains));
        Assert.False(SeedRule.IsProtected("notitatorrents.xyz", Settings.ProtectedDomains));
    }

    [Fact]
    public void ADownloadingTorrentIsNeverRemovable()
    {
        var verdict = SeedRule.Check(Torrent("tracker.example.org", 0.1, 0, progress: 0.99), Settings, Now);

        Assert.False(verdict.CanRemoveNow);
        Assert.Null(verdict.ExpectedAt);
    }

    [Fact]
    public void HostOfReadsTheAnnounceUrl()
    {
        Assert.Equal("shareisland.org", SeedRule.HostOf("https://ShareIsland.org/announce/abc"));
        Assert.Equal("", SeedRule.HostOf(null));
        Assert.Equal("", SeedRule.HostOf("non un url"));
    }
}
