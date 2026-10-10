using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Configuration;

/// <summary>
/// Impostazioni del plugin (spec G §6.8), salvate da Jellyfin in
/// plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml e cambiate
/// dalla pagina nella Dashboard. Proprietà pubbliche con get e set: le scrive
/// XmlSerializer.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>Raccogli i titoli nuovi della libreria e mandane il riepilogo (spec G §6.6).</summary>
    public bool NotifyNewTitles { get; set; } = true;

    /// <summary>
    /// Indirizzo di Seerr visto dal server Jellyfin, per esempio
    /// https://host/seerr (spec I §7.1). Vuoto: richieste spente.
    /// </summary>
    public string SeerrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Seerr (Impostazioni → Generali). Il file lo leggono solo gli admin.</summary>
    public string SeerrApiKey { get; set; } = string.Empty;

    /// <summary>Segreto che Seerr mette nel corpo del webhook (spec I §7.5).</summary>
    public string SeerrWebhookSecret { get; set; } = string.Empty;

    /// <summary>Token del bot Discord dei codici di recupero (spec L §7.1). Il file lo leggono solo gli admin.</summary>
    public string DiscordBotToken { get; set; } = string.Empty;

    /// <summary>Id del server Discord dove si cercano i membri.</summary>
    public string DiscordGuildId { get; set; } = string.Empty;

    /// <summary>Server SMTP delle email di recupero.</summary>
    public string SmtpHost { get; set; } = string.Empty;

    /// <summary>Porta SMTP con STARTTLS (di solito 587).</summary>
    public int SmtpPort { get; set; } = 587;

    public string SmtpUser { get; set; } = string.Empty;

    /// <summary>Password SMTP. Il file lo leggono solo gli admin.</summary>
    public string SmtpPassword { get; set; } = string.Empty;

    /// <summary>Indirizzo del mittente; il nome visualizzato è "WonderFlix".</summary>
    public string MailFrom { get; set; } = string.Empty;

    /// <summary>Ogni quanti giorni il promemoria a chi non ha contatti; 0 lo spegne.</summary>
    public int ContactReminderDays { get; set; } = 14;

    /// <summary>
    /// La Home dell'admin (spec M §6.2): gli id delle righe accese, in ordine,
    /// separati da virgole. Null: mai impostata, vale l'ordine predefinito
    /// dell'app; vuota: tutte le righe spente. Una stringa e non un elenco:
    /// con XmlSerializer null e vuoto restano diversi.
    /// </summary>
    public string? HomeRows { get; set; }

    /// <summary>
    /// Indirizzo di Sonarr visto dal server Jellyfin, con l'UrlBase, per
    /// esempio https://host/sonarr (spec M §7.1). Vuoto: niente "Serie in arrivo".
    /// </summary>
    public string SonarrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Sonarr (Settings → General). Il file lo leggono solo gli admin.</summary>
    public string SonarrApiKey { get; set; } = string.Empty;

    /// <summary>Indirizzo di Radarr, come Sonarr. Vuoto: niente "Film in arrivo".</summary>
    public string RadarrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Radarr. Il file lo leggono solo gli admin.</summary>
    public string RadarrApiKey { get; set; } = string.Empty;

    /// <summary>Giorni di "Serie in arrivo", da 1 a 60.</summary>
    public int UpcomingSeriesDays { get; set; } = 7;

    /// <summary>Giorni di "Film in arrivo" (uscita digitale), da 1 a 365.</summary>
    public int UpcomingMoviesDays { get; set; } = 90;
}
