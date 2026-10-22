namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Perché una chiamata a Seerr non è riuscita (spec I §7.3).</summary>
public enum SeerrError
{
    /// <summary>Indirizzo o chiave mancanti nella configurazione.</summary>
    NotConfigured,

    /// <summary>Seerr irraggiungibile, lento o con una risposta inattesa.</summary>
    Unavailable,

    /// <summary>Chiave API rifiutata.</summary>
    Auth,

    NoPermission,

    QuotaExceeded,

    Blocklisted,

    AlreadyRequested,

    /// <summary>Le stagioni sono già tutte chieste o presenti (il 202 di Seerr).</summary>
    NothingToRequest,

    /// <summary>L'utente non ha un account Seerr e l'import non l'ha creato.</summary>
    AccountUnavailable,

    /// <summary>Titolo o richiesta che Seerr non conosce.</summary>
    NotFound,

    /// <summary>Parametri sbagliati.</summary>
    BadRequest,
}

/// <summary>Errore di Seerr già classificato. Il messaggio non contiene mai la chiave.</summary>
public sealed class SeerrException : Exception
{
    public SeerrException(SeerrError error, Exception? inner = null)
        : base("Seerr: " + error, inner)
    {
        Error = error;
    }

    public SeerrError Error { get; }
}
