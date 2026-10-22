using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Sonarr e Radarr dalla configurazione del plugin.</summary>
public sealed class PluginArrSettings : IArrSettings
{
    // Si legge ogni volta, come PluginSeerrSettings. Senza plugin (nei test)
    // niente indirizzi e i giorni predefiniti.
    private static PluginConfiguration? Config => Plugin.Instance?.Configuration;

    public ArrEndpoint Sonarr => Endpoint(Config?.SonarrUrl, Config?.SonarrApiKey);

    public ArrEndpoint Radarr => Endpoint(Config?.RadarrUrl, Config?.RadarrApiKey);

    public int SeriesDays => ClampDays(Config?.UpcomingSeriesDays ?? ArrLimits.DefaultSeriesDays, ArrLimits.MaxSeriesDays);

    public int MovieDays => ClampDays(Config?.UpcomingMoviesDays ?? ArrLimits.DefaultMovieDays, ArrLimits.MaxMovieDays);

    /// <summary>Senza spazi ai lati e senza "/" finale; null diventa vuoto.</summary>
    internal static ArrEndpoint Endpoint(string? url, string? key) =>
        new((url ?? string.Empty).Trim().TrimEnd('/'), (key ?? string.Empty).Trim());

    /// <summary>Un numero scritto male nella Dashboard (0, 1000) non allarga né spegne la riga.</summary>
    internal static int ClampDays(int days, int max) => Math.Clamp(days, ArrLimits.MinDays, max);
}
