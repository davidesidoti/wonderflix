namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Sonarr (le serie) o Radarr (i film).</summary>
public enum ArrKind
{
    Sonarr,
    Radarr,
}

/// <summary>Indirizzo (senza "/" finale) e chiave di Sonarr o Radarr.</summary>
public sealed record ArrEndpoint(string Url, string ApiKey)
{
    public static readonly ArrEndpoint None = new(string.Empty, string.Empty);

    /// <summary>Indirizzo e chiave ci sono: la riga "in arrivo" è accesa.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Url) && !string.IsNullOrWhiteSpace(ApiKey);

    // Il ToString dei record stamperebbe la chiave.
    public override string ToString() => $"ArrEndpoint {{ Url = {Url} }}";
}

/// <summary>I giorni delle righe "in arrivo" (spec M §7.1).</summary>
public static class ArrLimits
{
    public const int MinDays = 1;

    public const int DefaultSeriesDays = 7;

    public const int MaxSeriesDays = 60;

    public const int DefaultMovieDays = 90;

    public const int MaxMovieDays = 365;
}

/// <summary>Il collegamento a Sonarr e Radarr. Va letto ogni volta: l'admin lo cambia dalla Dashboard.</summary>
public interface IArrSettings
{
    ArrEndpoint Sonarr { get; }

    ArrEndpoint Radarr { get; }

    /// <summary>Giorni di "Serie in arrivo", già fra 1 e 60.</summary>
    int SeriesDays { get; }

    /// <summary>Giorni di "Film in arrivo", già fra 1 e 365.</summary>
    int MovieDays { get; }
}

public static class ArrSettingsExtensions
{
    public static ArrEndpoint Endpoint(this IArrSettings settings, ArrKind kind) =>
        kind == ArrKind.Sonarr ? settings.Sonarr : settings.Radarr;
}
