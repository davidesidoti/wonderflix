namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Il collegamento a Seerr (spec I §7.1). Va letto ogni volta: l'admin lo cambia dalla Dashboard.</summary>
public interface ISeerrSettings
{
    /// <summary>Indirizzo senza "/" finale; vuoto se non impostato.</summary>
    string Url { get; }

    string ApiKey { get; }

    string WebhookSecret { get; }
}

public static class SeerrSettingsExtensions
{
    /// <summary>Indirizzo e chiave ci sono: la funzione "requests" è accesa.</summary>
    public static bool IsConfigured(this ISeerrSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.Url) && !string.IsNullOrWhiteSpace(settings.ApiKey);
}
