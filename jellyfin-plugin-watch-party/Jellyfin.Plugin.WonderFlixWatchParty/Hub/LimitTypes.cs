namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti che non sono tipi di evento (spec F §6.9, spec L §7.5). La chiave
/// passata a <see cref="RateLimiter.TryAcquire"/> è l'id dell'utente
/// (formato "N"); per il recupero è il nome scritto (in minuscolo), e "*"
/// per i limiti di tutti.
/// </summary>
public static class LimitTypes
{
    /// <summary>Nuove richieste di amicizia.</summary>
    public const string FriendRequests = "FriendRequests";

    /// <summary>Ricerche di utenti.</summary>
    public const string Searches = "Searches";

    /// <summary>Codici dei party privati provati (ogni tentativo conta).</summary>
    public const string CodeAttempts = "CodeAttempts";

    /// <summary>Destinatari degli inviti ai party.</summary>
    public const string Invites = "Invites";

    /// <summary>Richieste di recupero per nome scritto: una al minuto (spec L §7.5).</summary>
    public const string RecoveryStartMinute = "RecoveryStartMinute";

    /// <summary>Richieste di recupero per nome scritto: cinque all'ora.</summary>
    public const string RecoveryStartHour = "RecoveryStartHour";

    /// <summary>Richieste di recupero di tutti insieme (chiave "*").</summary>
    public const string RecoveryStartGlobal = "RecoveryStartGlobal";

    /// <summary>Codici di recupero sbagliati per nome scritto.</summary>
    public const string RecoveryFail = "RecoveryFail";

    /// <summary>
    /// Codici di recupero sbagliati di tutti insieme (chiave "*"): limita
    /// anche la memoria dei limiti per nomi inventati.
    /// </summary>
    public const string RecoveryFailGlobal = "RecoveryFailGlobal";

    /// <summary>Codici per collegare un contatto, per utente: uno al minuto.</summary>
    public const string LinkStartMinute = "LinkStartMinute";

    /// <summary>Codici per collegare un contatto, per utente: cinque all'ora.</summary>
    public const string LinkStartHour = "LinkStartHour";
}
