using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
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
}
