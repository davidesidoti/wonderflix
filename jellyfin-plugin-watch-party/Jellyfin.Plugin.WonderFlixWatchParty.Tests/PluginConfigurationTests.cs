using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginConfigurationTests
{
    [Fact]
    public void NewTitlesAreOnByDefaultAndTheSettingSurvivesTheXml()
    {
        Assert.True(new PluginConfiguration().NotifyNewTitles);

        // Jellyfin salva la configurazione con XmlSerializer.
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration { NotifyNewTitles = false });
        using var reader = new StringReader(writer.ToString());

        Assert.False(((PluginConfiguration)serializer.Deserialize(reader)!).NotifyNewTitles);
    }

    [Fact]
    public void WithoutThePluginInstanceNewTitlesStayOn()
    {
        // Nei test Jellyfin non crea il plugin: vale il predefinito.
        Assert.True(new PluginNewTitlesSettings().NotifyNewTitles);
    }

    [Fact]
    public void SeerrSettingsAreEmptyByDefaultAndSurviveTheXml()
    {
        var empty = new PluginConfiguration();
        Assert.Equal(string.Empty, empty.SeerrUrl);
        Assert.Equal(string.Empty, empty.SeerrApiKey);
        Assert.Equal(string.Empty, empty.SeerrWebhookSecret);

        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration
        {
            SeerrUrl = "https://host/seerr",
            SeerrApiKey = "key",
            SeerrWebhookSecret = "secret",
        });
        using var reader = new StringReader(writer.ToString());
        var read = (PluginConfiguration)serializer.Deserialize(reader)!;

        Assert.Equal("https://host/seerr", read.SeerrUrl);
        Assert.Equal("key", read.SeerrApiKey);
        Assert.Equal("secret", read.SeerrWebhookSecret);
    }

    [Fact]
    public void WithoutThePluginInstanceSeerrIsNotConfigured()
    {
        var settings = new PluginSeerrSettings();
        Assert.Equal(string.Empty, settings.Url);
        Assert.Equal(string.Empty, settings.ApiKey);
        Assert.False(settings.IsConfigured());
    }

    [Theory]
    [InlineData("https://host/seerr", "key", true)]
    [InlineData("", "key", false)]
    [InlineData("https://host/seerr", " ", false)]
    public void SeerrIsConfiguredWithUrlAndKey(string url, string key, bool configured) =>
        Assert.Equal(configured, new FakeSeerrSettings { Url = url, ApiKey = key }.IsConfigured());

    [Fact]
    public void TheHomeLayoutKeepsNeverSetApartFromAllOffThroughTheXml()
    {
        Assert.Null(new PluginConfiguration().HomeRows);
        Assert.Null(RoundTrip(new PluginConfiguration()).HomeRows);
        Assert.Equal(string.Empty, RoundTrip(new PluginConfiguration { HomeRows = string.Empty }).HomeRows);
        Assert.Equal("nextUp,resume", RoundTrip(new PluginConfiguration { HomeRows = "nextUp,resume" }).HomeRows);
    }

    [Fact]
    public void WithoutThePluginInstanceTheHomeLayoutIsTheDefaultAndCannotBeSaved()
    {
        var store = new PluginHomeLayoutStore();
        Assert.Null(store.Rows);
        Assert.Throws<InvalidOperationException>(() => store.Save(["resume"]));
    }

    [Fact]
    public void SonarrAndRadarrAreEmptyByDefaultAndSurviveTheXml()
    {
        var empty = new PluginConfiguration();
        Assert.Equal(string.Empty, empty.SonarrUrl);
        Assert.Equal(string.Empty, empty.SonarrApiKey);
        Assert.Equal(string.Empty, empty.RadarrUrl);
        Assert.Equal(string.Empty, empty.RadarrApiKey);
        Assert.Equal(7, empty.UpcomingSeriesDays);
        Assert.Equal(90, empty.UpcomingMoviesDays);

        var read = RoundTrip(new PluginConfiguration
        {
            SonarrUrl = "https://host/sonarr",
            SonarrApiKey = "s",
            RadarrUrl = "https://host/radarr",
            RadarrApiKey = "r",
            UpcomingSeriesDays = 14,
            UpcomingMoviesDays = 30,
        });
        Assert.Equal("https://host/sonarr", read.SonarrUrl);
        Assert.Equal("s", read.SonarrApiKey);
        Assert.Equal("https://host/radarr", read.RadarrUrl);
        Assert.Equal("r", read.RadarrApiKey);
        Assert.Equal(14, read.UpcomingSeriesDays);
        Assert.Equal(30, read.UpcomingMoviesDays);
    }

    [Fact]
    public void WithoutThePluginInstanceSonarrAndRadarrAreOffWithTheDefaultDays()
    {
        var settings = new PluginArrSettings();
        Assert.False(settings.Sonarr.IsConfigured);
        Assert.False(settings.Radarr.IsConfigured);
        Assert.Equal(7, settings.SeriesDays);
        Assert.Equal(90, settings.MovieDays);
    }

    [Theory]
    [InlineData(" https://host/sonarr/ ", " key ", "https://host/sonarr", "key", true)]
    [InlineData("https://host/sonarr", "", "https://host/sonarr", "", false)]
    [InlineData("", "key", "", "key", false)]
    [InlineData(null, null, "", "", false)]
    public void AnEndpointIsTrimmedAndNeedsBothAddressAndKey(
        string? url, string? key, string expectedUrl, string expectedKey, bool configured)
    {
        var endpoint = PluginArrSettings.Endpoint(url, key);
        Assert.Equal(expectedUrl, endpoint.Url);
        Assert.Equal(expectedKey, endpoint.ApiKey);
        Assert.Equal(configured, endpoint.IsConfigured);
    }

    [Theory]
    [InlineData(0, 60, 1)]
    [InlineData(-5, 60, 1)]
    [InlineData(14, 60, 14)]
    [InlineData(1000, 60, 60)]
    [InlineData(1000, 365, 365)]
    public void DaysStayInTheirRange(int days, int max, int expected) =>
        Assert.Equal(expected, PluginArrSettings.ClampDays(days, max));

    [Fact]
    public void AnEndpointNeverPrintsItsKey()
    {
        Assert.DoesNotContain("segreta", new ArrEndpoint("https://host/sonarr", "segreta").ToString(), StringComparison.Ordinal);
    }

    // Come la salva e la rilegge Jellyfin.
    private static PluginConfiguration RoundTrip(PluginConfiguration config)
    {
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, config);
        using var reader = new StringReader(writer.ToString());
        return (PluginConfiguration)serializer.Deserialize(reader)!;
    }
}
