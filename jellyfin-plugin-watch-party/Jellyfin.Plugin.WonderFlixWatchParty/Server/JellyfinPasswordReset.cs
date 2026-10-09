using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La password nuova con IUserManager, poi tutte le sessioni chiuse:
/// RevokeUserTokens con un token vuoto non ne risparmia nessuna (spec L §3).
/// </summary>
public sealed class JellyfinPasswordReset(IUserManager userManager, ISessionManager sessionManager) : IPasswordReset
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
        await sessionManager.RevokeUserTokens(userId, string.Empty).ConfigureAwait(false);
    }
}
