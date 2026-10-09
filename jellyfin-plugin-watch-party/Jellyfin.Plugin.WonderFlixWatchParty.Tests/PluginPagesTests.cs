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
        Assert.Contains("WonderFlixWatchParty/Inbox/NewTitles", html);
        Assert.Contains("NotifyNewTitles", html);
        Assert.Contains("emby-checkbox", html);
        // Sezione Seerr (spec I §7.1).
        Assert.Contains("SeerrUrl", html);
        Assert.Contains("SeerrApiKey", html);
        Assert.Contains("SeerrWebhookSecret", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Test", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Admin", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Webhook", html);
        Assert.Contains("'{{extra}}': []", html);
        Assert.Contains("requestedBy_jellyfinUserId", html);
        Assert.Contains("crypto.getRandomValues", html);
        // Recupero della password (spec L §7.1).
        Assert.Contains("DiscordBotToken", html);
        Assert.Contains("DiscordGuildId", html);
        Assert.Contains("SmtpHost", html);
        Assert.Contains("SmtpPort", html);
        Assert.Contains("SmtpUser", html);
        Assert.Contains("SmtpPassword", html);
        Assert.Contains("MailFrom", html);
        Assert.Contains("ContactReminderDays", html);
        Assert.Contains("WonderFlixWatchParty/Account/Admin/Status", html);
        Assert.Contains("WonderFlixWatchParty/Account/Admin/Test", html);
        // La prova sta fuori dal form delle impostazioni: Invio nei suoi campi non deve salvarle.
        var formEnd = html.IndexOf("</form>", html.IndexOf("id=\"WonderFlixRecoveryForm\"", StringComparison.Ordinal), StringComparison.Ordinal);
        Assert.True(formEnd > 0);
        Assert.True(html.IndexOf("id=\"WonderFlixTestDiscord\"", StringComparison.Ordinal) > formEnd);
        Assert.True(html.IndexOf("id=\"WonderFlixTestEmail\"", StringComparison.Ordinal) > formEnd);
        Assert.True(html.IndexOf("id=\"WonderFlixRecoveryTest\"", StringComparison.Ordinal) > formEnd);
        Assert.True(html.IndexOf("id=\"WonderFlixRecoveryResult\"", StringComparison.Ordinal) > formEnd);
        // L'id con cui la pagina legge e salva la configurazione è quello del plugin.
        Assert.Contains(Plugin.PluginId.ToString(), html);
    }
}
