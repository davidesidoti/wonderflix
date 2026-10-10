namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Perché una chiamata a Sonarr o Radarr non è riuscita (spec M §7.4).</summary>
public enum ArrError
{
    /// <summary>Indirizzo o chiave mancanti nella configurazione.</summary>
    NotConfigured,

    /// <summary>Chiave rifiutata (401 o 403).</summary>
    Unauthorized,

    /// <summary>Irraggiungibile, lento, o con una risposta inattesa (404, 5xx, redirect, non JSON).</summary>
    Unreachable,
}

/// <summary>Errore di Sonarr o Radarr già classificato. Il messaggio non contiene mai la chiave.</summary>
public sealed class ArrException : Exception
{
    public ArrException(ArrError error, Exception? inner = null)
        : base("Sonarr/Radarr: " + error, inner)
    {
        Error = error;
    }

    public ArrError Error { get; }
}

/// <summary>I codici di "Error" nelle risposte di Upcoming (spec M §7.4; decisione 1 del piano 19a).</summary>
public static class UpcomingErrors
{
    public const string NotConfigured = "NotConfigured";

    public const string Unauthorized = "Unauthorized";

    public const string Unreachable = "Unreachable";

    public static string Code(ArrError error) => error switch
    {
        ArrError.NotConfigured => NotConfigured,
        ArrError.Unauthorized => Unauthorized,
        _ => Unreachable,
    };
}
