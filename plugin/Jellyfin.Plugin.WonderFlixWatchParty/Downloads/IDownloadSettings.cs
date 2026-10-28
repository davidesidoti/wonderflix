using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Il punteggio minimo di un profilo e quello che basta ("va bene così"); null: nessun obiettivo.</summary>
public sealed record ProfileThresholds(int MinScore, int? TargetScore);

/// <summary>Le impostazioni dei download automatici. Vanno lette ogni volta: l'admin le cambia dalla Dashboard.</summary>
public interface IDownloadSettings
{
    bool Enabled { get; }

    /// <summary>GB all'ora minimi, già fra 0,1 e 20.</summary>
    double MinGbPerHour { get; }

    /// <summary>Le soglie del profilo: la riga dell'admin, altrimenti quelle predefinite.</summary>
    ProfileThresholds For(ArrKind kind, int profileId, string? profileName);
}

/// <summary>I valori predefiniti, quando l'admin non ha scritto una riga per il profilo (decisione 8).</summary>
public static class DownloadDefaults
{
    public const double MinGbPerHour = 0.8;

    public const double MinGbPerHourLow = 0.1;

    public const double MinGbPerHourHigh = 20;

    public const int DefaultMinScore = 50;

    public const int DefaultTargetScore = 150;

    public const int AnimeMinScore = 1;

    /// <summary>Con "anime" nel nome (senza badare alle maiuscole): minimo 1 e nessun obiettivo; altrimenti 50 e 150.</summary>
    public static ProfileThresholds For(string? profileName) =>
        profileName?.Contains("anime", StringComparison.OrdinalIgnoreCase) == true
            ? new ProfileThresholds(AnimeMinScore, null)
            : new ProfileThresholds(DefaultMinScore, DefaultTargetScore);
}
