using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le impostazioni dello spazio dalla configurazione del plugin (spec U §7.1).</summary>
public sealed class PluginSpaceSettings : ISpaceSettings
{
    // Senza plugin (nei test) valgono i valori iniziali della configurazione: una sola fonte per i predefiniti.
    private static readonly PluginConfiguration Defaults = new();

    // Si legge ogni volta, come PluginDownloadSettings.
    private static PluginConfiguration Config => Plugin.Instance?.Configuration ?? Defaults;

    public string QbitUrl => Config.SpaceQbitUrl;

    public string QbitUser => Config.SpaceQbitUser;

    public string QbitPassword => Config.SpaceQbitPassword;

    public int StaleMonths => Clamp(Config.SpaceStaleMonths, 1, 60, Defaults.SpaceStaleMonths);

    public int RequestGraceDays => Clamp(Config.SpaceRequestGraceDays, 0, 365, Defaults.SpaceRequestGraceDays);

    public int LowRating => Clamp(Config.SpaceLowRating, 1, 10, Defaults.SpaceLowRating);

    public int HighRating => Clamp(Config.SpaceHighRating, 1, 10, Defaults.SpaceHighRating);

    public int MinRatings => Clamp(Config.SpaceMinRatings, 1, 20, Defaults.SpaceMinRatings);

    public double HeavyGbPerHour => Clamp(Config.SpaceHeavyGbPerHour, 0.5, 50, Defaults.SpaceHeavyGbPerHour);

    public SeedSettings Seed => new(
        SplitDomains(Config.SpaceSeedTrackers),
        Clamp(Config.SpaceSeedRatio, 0, 100, Defaults.SpaceSeedRatio),
        Clamp(Config.SpaceSeedDays, 0, 365, Defaults.SpaceSeedDays));

    public IReadOnlyList<string> ScanFolders => SplitFolders(Config.SpaceScanFolders);

    public string QuotaFile => Config.SpaceQuotaFile;

    /// <summary>I domini separati da virgole o spazi, in minuscolo, senza vuoti.</summary>
    internal static IReadOnlyList<string> SplitDomains(string? csv) =>
        (csv ?? string.Empty)
            .Split([',', ' ', '\t', '\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(d => d.ToLowerInvariant())
            .ToList();

    /// <summary>Una cartella per riga, solo percorsi assoluti (con <c>/</c> iniziale), senza <c>/</c> finale: il plugin cancella solo lì dentro.</summary>
    internal static IReadOnlyList<string> SplitFolders(string? lines) =>
        (lines ?? string.Empty)
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim().TrimEnd('/'))
            .Where(l => l.StartsWith('/'))
            .ToList();

    /// <summary>Un valore fuori dall'intervallo torna al predefinito.</summary>
    internal static int Clamp(int value, int min, int max, int fallback) =>
        value >= min && value <= max ? value : fallback;

    /// <summary>Come sopra per i numeri con la virgola; anche un valore non numerico torna al predefinito.</summary>
    internal static double Clamp(double value, double min, double max, double fallback) =>
        value >= min && value <= max ? value : fallback;
}
