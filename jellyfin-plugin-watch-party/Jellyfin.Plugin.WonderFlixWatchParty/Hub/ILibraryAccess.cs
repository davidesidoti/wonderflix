namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un elemento in riproduzione: il suo id e quello della locandina (la serie, per un episodio).</summary>
public sealed record PlayingItem(Guid ItemId, Guid ImageItemId);

/// <summary>
/// La libreria come serve alla cassetta delle notifiche (adattatore di
/// ISessionManager, ILibraryManager e IUserManager).
/// </summary>
public interface ILibraryAccess
{
    /// <summary>L'elemento in riproduzione nella sessione; null se nessuno o se la sessione non c'è.</summary>
    PlayingItem? NowPlaying(string sessionId);

    /// <summary>
    /// L'utente può vedere l'elemento (librerie e limiti d'età del profilo),
    /// anche senza una sessione aperta; false se uno dei due non esiste.
    /// </summary>
    bool CanSee(Guid userId, Guid itemId);

    /// <summary>
    /// Il profilo ha limiti sui contenuti: classificazione massima, tag
    /// bloccati o consentiti, elementi senza classificazione bloccati. Un
    /// titolo senza metadati non ha né classificazione né tag, e quei limiti
    /// non lo fermerebbero. True anche se l'utente non esiste.
    /// </summary>
    bool HasContentLimits(Guid userId);
}
