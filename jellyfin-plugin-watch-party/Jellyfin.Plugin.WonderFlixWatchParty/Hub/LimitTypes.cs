namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti che non sono tipi di evento (spec F §6.9, spec L §7.5). La chiave
/// passata a <see cref="RateLimiter.TryAcquire"/> è l'id dell'utente
/// (formato "N"); per il recupero è il nome scritto (in maiuscolo), e "*"
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

    /// <summary>
    /// Richieste di recupero per nome scritto: dieci al giorno. Frena i codici
    /// a raffica mandati a una persona e il consumo della quota del servizio
    /// email.
    /// </summary>
    public const string RecoveryStartDay = "RecoveryStartDay";

    /// <summary>Richieste di recupero di tutti insieme (chiave "*").</summary>
    public const string RecoveryStartGlobal = "RecoveryStartGlobal";

    /// <summary>Codici di recupero sbagliati per nome scritto, in un'ora.</summary>
    public const string RecoveryFail = "RecoveryFail";

    /// <summary>
    /// Codici di recupero sbagliati per nome scritto, in un giorno: con i soli
    /// limiti orari un tentativo lento e continuo resterebbe possibile
    /// (spec L §7.5).
    /// </summary>
    public const string RecoveryFailDay = "RecoveryFailDay";

    /// <summary>
    /// Codici di recupero sbagliati di tutti insieme in un giorno (chiave
    /// "*"): limita anche la memoria dei limiti per nomi inventati.
    /// </summary>
    public const string RecoveryFailGlobal = "RecoveryFailGlobal";

    /// <summary>
    /// Codici per collegare un contatto, per utente e canale: uno al minuto.
    /// Si spende solo quando parte un codice, quindi un nome sbagliato si riscrive subito.
    /// </summary>
    public const string LinkStartMinute = "LinkStartMinute";

    /// <summary>Codici per collegare un contatto, per utente: cinque all'ora.</summary>
    public const string LinkStartHour = "LinkStartHour";

    /// <summary>
    /// Controlli della password attuale per cambiare i contatti, per utente:
    /// dieci all'ora. Chi ha la sessione non può provare password all'infinito.
    /// </summary>
    public const string PasswordChecks = "PasswordChecks";
}
