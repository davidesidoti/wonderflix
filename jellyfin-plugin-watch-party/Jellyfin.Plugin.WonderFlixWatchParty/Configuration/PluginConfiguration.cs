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
}
