using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
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
}
