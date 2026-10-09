namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// La password attuale dell'utente (spec L §8): chi ha solo una sessione
/// aperta non può cambiare i contatti per il recupero. Non lancia: un errore
/// è false (un annullamento esce come OperationCanceledException).
/// </summary>
public interface IPasswordCheck
{
    /// <summary>true se è la password attuale dell'utente; vuota per un account senza password.</summary>
    Task<bool> IsCurrentPasswordAsync(Guid userId, string password);
}
