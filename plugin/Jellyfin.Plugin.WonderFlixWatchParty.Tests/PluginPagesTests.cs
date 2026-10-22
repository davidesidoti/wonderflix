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
        Assert.Contains("Password recovery test", html);
        // La prova usa le impostazioni salvate; un nome Discord scritto male è un "target non valido" come l'email.
        Assert.Contains("Save first: the test uses the saved settings.", html);
        Assert.Contains("InvalidTarget: 'not a valid user name or address'", html);

        // Un campo numerico vuoto non si salva con un valore a caso: serve "required", e il ripiego è il valore appena letto.
        Assert.Contains(" required", TagWithId(html, "WonderFlixSmtpPort"));
        Assert.Contains(" required", TagWithId(html, "WonderFlixContactReminderDays"));
        Assert.Contains("numberIn(recoveryFields.SmtpPort, config.SmtpPort)", html);
        Assert.Contains("numberIn(recoveryFields.ContactReminderDays, config.ContactReminderDays)", html);

        // L'errore di salvataggio ha il suo spazio dentro il form, e la prova non lo cancella (né il contrario).
        var formStart = html.IndexOf("id=\"WonderFlixRecoveryForm\"", StringComparison.Ordinal);
        var saveResult = html.IndexOf("id=\"WonderFlixRecoverySaveResult\"", StringComparison.Ordinal);
        Assert.True(saveResult > formStart && saveResult < formEnd);
        Assert.Contains("recoverySaveResult.textContent = 'Settings not saved.'", html);
        Assert.DoesNotContain("recoveryResult.textContent = 'Settings not saved.'", html);

        // Senza la configurazione letta, Salva rifiuta: sovrascriverebbe le impostazioni con campi vuoti.
        Assert.Contains("recoveryLoaded", html);
        Assert.Contains("Settings not loaded: reload the page.", html);

        // I gestori di password del browser non devono offrire (né salvare) l'accesso a Jellyfin in questi campi.
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixDiscordBotToken"));
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixSmtpPassword"));
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixSeerrApiKey"));

        // I lettori di schermo leggono lo stato e gli esiti quando cambiano.
        Assert.Contains("aria-live=\"polite\"", TagWithId(html, "WonderFlixRecoveryStatus"));
        Assert.Contains("aria-live=\"polite\"", TagWithId(html, "WonderFlixRecoverySaveResult"));
        Assert.Contains("aria-live=\"polite\"", TagWithId(html, "WonderFlixRecoveryResult"));

        // Lo stato mostra l'ultimo errore di ogni canale.
        Assert.Contains("(last error: ", html);

        // Sonarr e Radarr (spec M §7.1), con le protezioni del recupero:
        // niente Salva prima di aver letto, numeri obbligatori, chiavi non offerte dal browser.
        Assert.Contains("SonarrUrl", html);
        Assert.Contains("SonarrApiKey", html);
        Assert.Contains("RadarrUrl", html);
        Assert.Contains("RadarrApiKey", html);
        Assert.Contains("UpcomingSeriesDays", html);
        Assert.Contains("UpcomingMoviesDays", html);
        Assert.Contains("WonderFlixWatchParty/Upcoming/Test", html);
        Assert.Contains("arrLoaded", html);
        Assert.Contains("numberIn(arrFields.UpcomingSeriesDays, config.UpcomingSeriesDays)", html);
        Assert.Contains("numberIn(arrFields.UpcomingMoviesDays, config.UpcomingMoviesDays)", html);
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixSonarrApiKey"));
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixRadarrApiKey"));
        Assert.Contains(" required", TagWithId(html, "WonderFlixUpcomingSeriesDays"));
        Assert.Contains(" required", TagWithId(html, "WonderFlixUpcomingMoviesDays"));
        Assert.Contains("aria-live=\"polite\"", TagWithId(html, "WonderFlixArrResult"));
        // Uno stato senza versione non diventa "connected (null)".
        Assert.Contains("result.Version || 'unknown version'", html);

        // L'id con cui la pagina legge e salva la configurazione è quello del plugin.
        Assert.Contains(Plugin.PluginId.ToString(), html);
    }

    // Il tag (da "<" a ">") che porta questo id.
    private static string TagWithId(string html, string id)
    {
        var at = html.IndexOf($"id=\"{id}\"", StringComparison.Ordinal);
        Assert.True(at > 0, id);
        var start = html.LastIndexOf('<', at);
        return html[start..(html.IndexOf('>', at) + 1)];
    }
}
