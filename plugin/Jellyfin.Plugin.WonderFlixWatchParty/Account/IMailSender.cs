namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Le email dei codici (spec L §7.3). Non lancia: gli errori sono esiti.
/// Solo l'annullamento di chi chiama esce come OperationCanceledException.
/// </summary>
public interface IMailSender
{
    /// <summary>Un'email di solo testo a questo indirizzo.</summary>
    Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken);
}
