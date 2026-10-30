using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginSpaceSettingsTests
{
    [Fact]
    public void DomainsAreSplitAndLowercased() =>
        Assert.Equal(["itatorrents.xyz", "shareisland.org"], PluginSpaceSettings.SplitDomains(" ItaTorrents.xyz, shareisland.org,,"));

    [Fact]
    public void FoldersMustBeAbsolute() =>
        Assert.Equal(["/home/a", "/home/b"], PluginSpaceSettings.SplitFolders("/home/a/\nrelativo\n\n/home/b"));

    [Fact]
    public void FoldersAcceptWindowsLineEndings() =>
        Assert.Equal(["/home/a", "/home/b"], PluginSpaceSettings.SplitFolders("/home/a\r\n/home/b\r\n"));

    [Fact]
    public void OutOfRangeFallsBack()
    {
        Assert.Equal(6, PluginSpaceSettings.Clamp(0, 1, 60, 6));
        Assert.Equal(6, PluginSpaceSettings.Clamp(61, 1, 60, 6));
        Assert.Equal(1, PluginSpaceSettings.Clamp(1, 1, 60, 6));
        Assert.Equal(60, PluginSpaceSettings.Clamp(60, 1, 60, 6));
    }

    [Fact]
    public void OutOfRangeDoubleFallsBack()
    {
        Assert.Equal(4.0, PluginSpaceSettings.Clamp(double.NaN, 0.5, 50, 4.0));
        Assert.Equal(4.0, PluginSpaceSettings.Clamp(0.1, 0.5, 50, 4.0));
        Assert.Equal(4.0, PluginSpaceSettings.Clamp(51, 0.5, 50, 4.0));
        Assert.Equal(0.5, PluginSpaceSettings.Clamp(0.5, 0.5, 50, 4.0));
    }

    [Fact]
    public void WithoutPluginDefaultsApply()
    {
        var settings = new PluginSpaceSettings();
        Assert.Equal(6, settings.StaleMonths);
        Assert.Equal(60, settings.RequestGraceDays);
        Assert.Equal(2, settings.LowRating);
        Assert.Equal(4, settings.HighRating);
        Assert.Equal(2, settings.MinRatings);
        Assert.Equal(4.0, settings.HeavyGbPerHour);
        Assert.Equal(30, settings.Seed.Days);
        Assert.Equal(10.0, settings.Seed.Ratio);
        Assert.Equal(["itatorrents.xyz", "shareisland.org"], settings.Seed.ProtectedDomains);
        Assert.Equal(["/home/hashvps/downloads", "/home/hashvps/seedings"], settings.ScanFolders);
        Assert.Equal(string.Empty, settings.QbitUrl);
        Assert.Equal(string.Empty, settings.QuotaFile);
    }

    [Fact]
    public void ConfigurationDefaultsMatchTheSpec()
    {
        var config = new PluginConfiguration();
        Assert.Equal(string.Empty, config.SpaceQbitPassword);
        Assert.Equal(6, config.SpaceStaleMonths);
        Assert.Equal(60, config.SpaceRequestGraceDays);
        Assert.Equal("itatorrents.xyz,shareisland.org", config.SpaceSeedTrackers);
        Assert.Equal("/home/hashvps/downloads\n/home/hashvps/seedings", config.SpaceScanFolders);
    }
}
