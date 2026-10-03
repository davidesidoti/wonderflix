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
}
