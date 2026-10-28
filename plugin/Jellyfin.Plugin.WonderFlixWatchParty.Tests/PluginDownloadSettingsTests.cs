using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginDownloadSettingsTests
{
    private static ProfileThresholds For(string? name, params DownloadProfileRule[] rules) =>
        PluginDownloadSettings.Thresholds(rules, ArrKind.Sonarr, 3, name);

    [Theory]
    [InlineData("[Anime] 1080p")]
    [InlineData("Anime Main Profile")]
    public void AnimeProfilesHaveNoTarget(string name) =>
        Assert.Equal(new ProfileThresholds(1, null), For(name));

    [Theory]
    [InlineData("Main Profile")]
    [InlineData(null)]
    public void OtherProfilesAimAtOneFifty(string? name) =>
        Assert.Equal(new ProfileThresholds(50, 150), For(name));

    [Fact]
    public void AConfiguredRuleWins()
    {
        var rules = new[]
        {
            new DownloadProfileRule { Service = "Radarr", ProfileId = 3, MinScore = 1, TargetScore = 1 },
            new DownloadProfileRule { Service = "sonarr", ProfileId = 3, MinScore = 80, TargetScore = null },
        };

        // Stesso id, servizio diverso: conta solo la riga di Sonarr (senza badare alle maiuscole).
        Assert.Equal(new ProfileThresholds(80, null), For("Main Profile", rules));
        Assert.Equal(new ProfileThresholds(1, 1), PluginDownloadSettings.Thresholds(rules, ArrKind.Radarr, 3, "Anime"));
        Assert.Equal(new ProfileThresholds(1, null), PluginDownloadSettings.Thresholds(rules, ArrKind.Sonarr, 4, "Anime"));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(double.NaN)]
    [InlineData(50)]
    public void AWrongWeightFallsBack(double value) =>
        Assert.Equal(0.8, PluginDownloadSettings.ClampMinGbPerHour(value));

    [Theory]
    [InlineData(0.1)]
    [InlineData(2.5)]
    [InlineData(20)]
    public void AGoodWeightIsKept(double value) =>
        Assert.Equal(value, PluginDownloadSettings.ClampMinGbPerHour(value));

    [Fact]
    public void WithoutThePluginTheDownloadsAreOff()
    {
        var settings = new PluginDownloadSettings();

        Assert.False(settings.Enabled);
        Assert.Equal(0.8, settings.MinGbPerHour);
    }

    [Fact]
    public void TheRulesSurviveTheXml()
    {
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        Assert.Empty(new PluginConfiguration().DownloadProfileRules);

        var config = new PluginConfiguration
        {
            DownloadsEnabled = true,
            DownloadProfileRules =
            [
                new DownloadProfileRule { Service = "Radarr", ProfileId = 2, MinScore = 10, TargetScore = null },
                new DownloadProfileRule { Service = "Sonarr", ProfileId = 5, MinScore = 20, TargetScore = 90 },
            ],
        };
        using var writer = new StringWriter();
        serializer.Serialize(writer, config);
        using var reader = new StringReader(writer.ToString());
        var back = (PluginConfiguration)serializer.Deserialize(reader)!;

        Assert.True(back.DownloadsEnabled);
        Assert.Equal(0.8, back.DownloadsMinGbPerHour);
        Assert.Equal(2, back.DownloadProfileRules.Length);
        Assert.Null(back.DownloadProfileRules[0].TargetScore);
        Assert.Equal(90, back.DownloadProfileRules[1].TargetScore);
    }
}
