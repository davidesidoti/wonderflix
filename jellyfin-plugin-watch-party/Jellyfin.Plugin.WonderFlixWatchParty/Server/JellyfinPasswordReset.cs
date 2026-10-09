using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La password nuova con IUserManager, poi tutte le sessioni chiuse:
/// RevokeUserTokens con un token vuoto non ne risparmia nessuna (spec L §3).
/// </summary>
public sealed class JellyfinPasswordReset(
    IUserManager userManager,
    ISessionManager sessionManager,
    ILogger<JellyfinPasswordReset> logger) : IPasswordReset
{
    // Quale ChangePassword usare si decide una volta sola (vedi PasswordChanging).
    private static readonly Func<object, User, string, Task>? Change = PasswordChanging.For(typeof(IUserManager));

    public async Task ResetAsync(Guid userId, string newPassword)
    {
        // Con un id vuoto UserManager lancia un'altra eccezione: l'utente non c'è e basta.
        var user = (userId == Guid.Empty ? null : userManager.GetUserById(userId))
            ?? throw new ArgumentException("utente sconosciuto", nameof(userId));
        var change = Change ?? throw new MissingMemberException(typeof(IUserManager).FullName, "ChangePassword");
        await change(userManager, user, newPassword).ConfigureAwait(false);

        // La password è già cambiata e il codice è stato usato: se le sessioni
        // non si chiudono non è un recupero fallito, e chi ha chiamato non deve
        // credere che si possa riprovare. Si scrive nel registro e basta.
        try
        {
            await sessionManager.RevokeUserTokens(userId, string.Empty).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Password di {UserId} cambiata, ma sessioni non chiuse", userId.ToString("N"));
        }
    }
}
