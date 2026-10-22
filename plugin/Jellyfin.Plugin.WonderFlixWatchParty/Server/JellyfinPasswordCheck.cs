using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La password attuale controllata con Jellyfin (spec L §8): AuthenticateUser
/// di IUserManager, che ha la stessa firma nella 10.11.0 e nella 10.11.9.
/// Con isUserSession false Jellyfin non tocca LastLoginDate; una password
/// sbagliata conta come un accesso sbagliato (InvalidLoginAttemptCount), come
/// in jellyfin-web.
/// </summary>
public sealed class JellyfinPasswordCheck(IUserManager userManager, ILogger<JellyfinPasswordCheck> logger) : IPasswordCheck
{
    // Chi chiama ha già una sessione valida: il controllo dell'accesso remoto di Jellyfin qui non serve.
    private const string LoopbackEndPoint = "127.0.0.1";

    public async Task<bool> IsCurrentPasswordAsync(Guid userId, string password)
    {
        try
        {
            // Con un id vuoto UserManager lancia un'altra eccezione: l'utente non c'è e basta.
            var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
            if (user is null)
            {
                return false;
            }

            return await userManager.AuthenticateUser(user.Username, password, LoopbackEndPoint, isUserSession: false)
                .ConfigureAwait(false) is not null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // In Jellyfin 10.11 una password sbagliata di un utente che esiste torna come null (l'eccezione
            // del provider si ferma dentro UserManager), quindi qui non arriva. Qui arrivano un nome utente
            // sconosciuto, un utente disattivato, l'accesso remoto o l'orario del controllo parentale.
            // Nel registro vanno solo l'utente e il tipo dell'errore: mai la password.
            logger.LogWarning("Password attuale non verificata per {UserId}: {ExceptionType}", userId.ToString("N"), ex.GetType().Name);
            return false;
        }
    }
}
