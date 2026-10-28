using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I download automatici dalla configurazione del plugin.</summary>
public sealed class PluginDownloadSettings : IDownloadSettings
{
    // Si legge ogni volta, come PluginArrSettings. Senza plugin (nei test) tutto spento e predefinito.
    private static PluginConfiguration? Config => Plugin.Instance?.Configuration;

    public bool Enabled => Config?.DownloadsEnabled ?? false;

    public double MinGbPerHour => ClampMinGbPerHour(Config?.DownloadsMinGbPerHour ?? DownloadDefaults.MinGbPerHour);

    public ProfileThresholds For(ArrKind kind, int profileId, string? profileName) =>
        Thresholds(Config?.DownloadProfileRules, kind, profileId, profileName);

    /// <summary>Un peso fuori da 0,1–20 (o non un numero) torna a 0,8: non spegne né spalanca il filtro.</summary>
    internal static double ClampMinGbPerHour(double value) =>
        value is >= DownloadDefaults.MinGbPerHourLow and <= DownloadDefaults.MinGbPerHourHigh
            ? value
            : DownloadDefaults.MinGbPerHour;

    internal static ProfileThresholds Thresholds(IEnumerable<DownloadProfileRule>? rules, ArrKind kind, int profileId, string? profileName)
    {
        var rule = rules?.FirstOrDefault(r =>
            r.ProfileId == profileId && string.Equals(r.Service, kind.ToString(), StringComparison.OrdinalIgnoreCase));
        return rule is null ? DownloadDefaults.For(profileName) : new ProfileThresholds(rule.MinScore, rule.TargetScore);
    }
}
