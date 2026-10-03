using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginPagesTests
{
    [Fact]
    public void TheDashboardPageIsEmbeddedAndSendsAnnouncements()
    {
        var page = Assert.Single(Plugin.Pages);
        Assert.Equal("WonderFlixWatchParty", page.Name);
        Assert.Equal("WonderFlix Watch Party", page.DisplayName);
        Assert.True(page.EnableInMainMenu);

        using var stream = typeof(Plugin).Assembly.GetManifestResourceStream(page.EmbeddedResourcePath);
        Assert.NotNull(stream);
        using var reader = new StreamReader(stream);
        var html = reader.ReadToEnd();
        Assert.Contains("pluginConfigurationPage", html);
        Assert.Contains("WonderFlixWatchParty/Inbox/Announcements", html);
        Assert.Contains("maxlength=\"500\"", html);
    }
}
