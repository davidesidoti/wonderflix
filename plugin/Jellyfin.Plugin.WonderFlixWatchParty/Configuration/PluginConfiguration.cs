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
    /// Le righe nate dopo la 1.7.0 già accese una volta nella Home
    /// dell'admin (spec N §6.7), separate da virgole: una riga spenta dopo
    /// dall'admin non si riaccende. Null: nessuna.
    /// </summary>
    public string? HomeRowsSeen { get; set; }

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

    /// <summary>Download automatici accesi (spec T). Spenti per predefinito.</summary>
    public bool DownloadsEnabled { get; set; }

    /// <summary>GB all'ora sotto cui una release è scartata come troppo piccola (da 0,1 a 20).</summary>
    public double DownloadsMinGbPerHour { get; set; } = 0.8;

    /// <summary>Soglie di punteggio per profilo di qualità; un profilo senza riga usa quelle predefinite. Un array: XmlSerializer lo sa scrivere.</summary>
    public DownloadProfileRule[] DownloadProfileRules { get; set; } = [];

    /// <summary>Indirizzo di qBittorrent visto dal server Jellyfin (spec U §7.1). Vuoto: niente torrent nella pagina Spazio.</summary>
    public string SpaceQbitUrl { get; set; } = string.Empty;

    public string SpaceQbitUser { get; set; } = string.Empty;

    /// <summary>Password di qBittorrent. Il file lo leggono solo gli admin.</summary>
    public string SpaceQbitPassword { get; set; } = string.Empty;

    /// <summary>Mesi senza che nessuno apra un titolo perché sia fermo, da 1 a 60.</summary>
    public int SpaceStaleMonths { get; set; } = 6;

    /// <summary>Giorni in cui una richiesta recente protegge un titolo, da 0 a 365.</summary>
    public int SpaceRequestGraceDays { get; set; } = 60;

    /// <summary>Voto medio sotto il quale un titolo è poco gradito, da 1 a 5.</summary>
    public int SpaceLowRating { get; set; } = 2;

    /// <summary>Voto medio da cui un titolo si tiene, da 1 a 5.</summary>
    public int SpaceHighRating { get; set; } = 4;

    /// <summary>Voti minimi perché la media conti, da 1 a 20.</summary>
    public int SpaceMinRatings { get; set; } = 2;

    /// <summary>GB all'ora oltre i quali un file è pesante (da 0,5 a 50).</summary>
    public double SpaceHeavyGbPerHour { get; set; } = 4.0;

    /// <summary>Domini dei tracker privati con seed obbligatorio, separati da virgole.</summary>
    public string SpaceSeedTrackers { get; set; } = "itatorrents.xyz,shareisland.org";

    /// <summary>Rapporto di seed che sblocca la rimozione, da 0 a 100.</summary>
    public double SpaceSeedRatio { get; set; } = 10.0;

    /// <summary>Giorni di seed che sbloccano la rimozione, da 0 a 365.</summary>
    public int SpaceSeedDays { get; set; } = 30;

    /// <summary>Cartelle del server dove si cercano i file orfani, una per riga; il plugin cancella solo lì dentro.</summary>
    public string SpaceScanFolders { get; set; } = "/home/hashvps/downloads\n/home/hashvps/seedings";

    /// <summary>File dove un cron scrive la quota del seedbox. Vuoto: quota non configurata.</summary>
    public string SpaceQuotaFile { get; set; } = string.Empty;
}

/// <summary>Le soglie di un profilo di qualità di Radarr o Sonarr (spec T). <c>TargetScore</c> null: nessun obiettivo.</summary>
public class DownloadProfileRule
{
    /// <summary>"Radarr" o "Sonarr".</summary>
    public string Service { get; set; } = string.Empty;

    public int ProfileId { get; set; }

    public int MinScore { get; set; }

    public int? TargetScore { get; set; }
}
