using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La casella dalla configurazione del plugin.</summary>
public sealed class PluginNewTitlesSettings : INewTitlesSettings
{
    // Si legge ogni volta: salvando dalla Dashboard Jellyfin sostituisce
    // l'oggetto della configurazione. Senza plugin (nei test) vale il
    // predefinito.
    public bool NotifyNewTitles => Plugin.Instance?.Configuration.NotifyNewTitles ?? true;
}
