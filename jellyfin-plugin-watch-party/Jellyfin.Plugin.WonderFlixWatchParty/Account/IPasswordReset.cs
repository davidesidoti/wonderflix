namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Cambiare la password di un utente e chiuderne tutte le sessioni (spec L §7.4).</summary>
public interface IPasswordReset
{
    /// <summary>Lancia se l'utente non c'è o se Jellyfin non riesce.</summary>
    Task ResetAsync(Guid userId, string newPassword);
}
