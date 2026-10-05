using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Il collegamento a Seerr dalla configurazione del plugin.</summary>
public sealed class PluginSeerrSettings : ISeerrSettings
{
    // Si legge ogni volta, come PluginNewTitlesSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione. Senza
    // plugin (nei test) tutto vuoto.
    public string Url => (Plugin.Instance?.Configuration.SeerrUrl ?? string.Empty).Trim().TrimEnd('/');

    public string ApiKey => (Plugin.Instance?.Configuration.SeerrApiKey ?? string.Empty).Trim();

    public string WebhookSecret => (Plugin.Instance?.Configuration.SeerrWebhookSecret ?? string.Empty).Trim();
}
