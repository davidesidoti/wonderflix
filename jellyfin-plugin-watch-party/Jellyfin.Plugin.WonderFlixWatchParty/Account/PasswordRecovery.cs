using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Esito di <see cref="PasswordRecovery.Start"/>: subito. L'invio continua in Sending (i test lo aspettano).</summary>
public sealed record RecoveryStartResult(AccountError? Error, Task Sending);

/// <summary>Esito di <see cref="PasswordRecovery.CompleteAsync"/>. L'avviso "password cambiata" continua in Notifying.</summary>
public sealed record RecoveryCompleteResult(AccountError? Error, Task Notifying);

/// <summary>
/// Il recupero della password senza accesso (spec L §7.4, §8): un codice ai
/// contatti verificati, poi la password nuova con il codice. Le risposte
/// non dicono se un account esiste. Non vale per gli admin né per gli
/// utenti disattivati. Anche il codice mandato dall'admin passa da qui.
/// </summary>
public sealed class PasswordRecovery(
    IUserDirectory users,
    ContactRegistry contacts,
    CodeBook codes,
    RateLimiter limiter,
    AccountSender sender,
    IPasswordReset passwords,
    ILogger<PasswordRecovery> logger)
{
    /// <summary>Lunghezza minima di una password nuova (spec L §8).</summary>
    public const int MinPasswordLength = 6;

    /// <summary>Lunghezza massima di una password nuova.</summary>
    public const int MaxPasswordLength = 1024;

    /// <summary>Lunghezza massima di un nome utente scritto.</summary>
    public const int MaxUsernameLength = 256;

    /// <summary>La chiave dei limiti di tutti.</summary>
    internal const string EveryoneKey = "*";

    /// <summary>
    /// Chiede un codice. Risponde subito, uguale per tutti (tranne i limiti,
    /// che contano il nome scritto, esista o no). Dopo, in background: se
    /// l'utente può usare il recupero e ha contatti, il codice va a tutti.
    /// </summary>
    public RecoveryStartResult Start(string? username, string? language)
    {
        var name = Trimmed(username);
        if (name is null)
        {
            return new RecoveryStartResult(AccountError.Invalid, Task.CompletedTask);
        }

        var key = Key(name);
        if (!limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryStartGlobal)
            || !limiter.TryAcquire(key, LimitTypes.RecoveryStartMinute)
            || !limiter.TryAcquire(key, LimitTypes.RecoveryStartHour))
        {
            return new RecoveryStartResult(AccountError.RateLimited, Task.CompletedTask);
        }

        // Utente, contatti e invio non si vedono dal tempo di risposta.
        return new RecoveryStartResult(null, Task.Run(() => SendCodeAsync(name, language)));
    }

    /// <summary>
    /// La password nuova con il codice. Una password troppo corta o troppo
    /// lunga non consuma tentativi. Utente sconosciuto, non ammesso o codice
    /// sbagliato: InvalidCode, e conta per i limiti. Un errore di Jellyfin
    /// esce come eccezione.
    /// </summary>
    public async Task<RecoveryCompleteResult> CompleteAsync(string? username, string? code, string? newPassword, string? language)
    {
        var name = Trimmed(username);
        if (name is null)
        {
            return Done(AccountError.Invalid);
        }

        var key = Key(name);
        if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal)
            || limiter.IsLimited(key, LimitTypes.RecoveryFail)
            || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
        {
            return Done(AccountError.RateLimited);
        }

        if (newPassword is null || newPassword.Length < MinPasswordLength || newPassword.Length > MaxPasswordLength)
        {
            return Done(AccountError.WeakPassword);
        }

        var user = Eligible(name);
        var check = user is null ? CodeCheck.Wrong : codes.Check(user.Id, CodePurpose.Recovery, code);
        if (user is null || !check.Ok)
        {
            limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryFailGlobal);
            limiter.TryAcquire(key, LimitTypes.RecoveryFail);
            limiter.TryAcquire(key, LimitTypes.RecoveryFailDay);

            // Nel log si vede quando qualcuno prova a indovinare i codici: una volta
            // sola, quando il limite scatta (dopo si risponde 429 prima di arrivare qui),
            // e mai il testo scritto, che potrebbe essere un'email o contenere a capo.
            if (limiter.IsLimited(key, LimitTypes.RecoveryFail) || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
            {
                logger.LogWarning(
                    "Recupero della password fermato dai limiti per {Who}",
                    user is null ? "un nome che non è un utente" : user.Id.ToString("N"));
            }

            if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal))
            {
                logger.LogWarning("Recupero della password fermato per tutti: troppi codici sbagliati oggi");
            }

            return Done(AccountError.InvalidCode);
        }

        try
        {
            await passwords.ResetAsync(user.Id, newPassword).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Password di {UserId} non cambiata", user.Id);
            throw;
        }

        logger.LogInformation("Password di {UserId} cambiata con il codice di recupero", user.Id);

        // L'avviso non trattiene la risposta.
        return new RecoveryCompleteResult(null, Task.Run(() => NotifyChangedAsync(user, language)));
    }

    /// <summary>
    /// Il codice mandato dall'admin (spec L §7.4): la risposta dice com'è
    /// andata, e non ci sono i limiti del recupero.
    /// </summary>
    public async Task<AccountResult<AdminRecoveryResponse>> SendForAdminAsync(
        Guid userId, string? language, CancellationToken cancellationToken)
    {
        var user = users.GetUser(userId);
        if (user is null)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.UnknownUser);
        }

        if (user.IsAdmin || !user.Enabled)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.NotAllowed);
        }

        var mine = contacts.Get(userId);
        if (sender.Targets(mine).Count == 0)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.NoContacts);
        }

        var (code, _) = codes.Issue(userId, CodePurpose.Recovery);
        var sent = await sender.SendToAllAsync(mine, AccountMessages.Recovery(language, user.Name, code), cancellationToken)
            .ConfigureAwait(false);
        if (sent.Count == 0)
        {
            codes.Discard(userId, CodePurpose.Recovery);
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.SendFailed);
        }

        logger.LogInformation("Codice di recupero di {UserId} mandato dall'admin su {Count} canali", userId, sent.Count);
        return AccountResult<AdminRecoveryResponse>.Ok(new AdminRecoveryResponse(sent.Select(c => c.Name()).ToList()));
    }

    private async Task SendCodeAsync(string name, string? language)
    {
        try
        {
            var user = Eligible(name);
            if (user is null)
            {
                return;
            }

            var mine = contacts.Get(user.Id);
            if (sender.Targets(mine).Count == 0)
            {
                return;
            }

            var (code, _) = codes.Issue(user.Id, CodePurpose.Recovery);
            var sent = await sender.SendToAllAsync(mine, AccountMessages.Recovery(language, user.Name, code), CancellationToken.None)
                .ConfigureAwait(false);
            if (sent.Count == 0)
            {
                codes.Discard(user.Id, CodePurpose.Recovery);
                logger.LogWarning("Codice di recupero di {UserId} non mandato: nessun canale ha funzionato", user.Id);
                return;
            }

            logger.LogInformation("Codice di recupero di {UserId} mandato su {Count} canali", user.Id, sent.Count);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Codice di recupero non mandato");
        }
    }

    private async Task NotifyChangedAsync(UserRef user, string? language)
    {
        try
        {
            await sender.SendToAllAsync(contacts.Get(user.Id), AccountMessages.PasswordChanged(language, user.Name), CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Avviso del cambio password non mandato a {UserId}", user.Id);
        }
    }

    // L'utente può usare il recupero: esiste, è attivo e non è admin. Il nome senza maiuscole, come Jellyfin.
    private UserRef? Eligible(string name) =>
        users.GetUsers().FirstOrDefault(u => string.Equals(u.Name, name, StringComparison.OrdinalIgnoreCase))
            is { Enabled: true, IsAdmin: false } user
            ? user
            : null;

    private static string? Trimmed(string? raw)
    {
        var name = raw?.Trim();
        return string.IsNullOrEmpty(name) || name.Length > MaxUsernameLength ? null : name;
    }

    private static string Key(string name) => name.ToLowerInvariant();

    private static RecoveryCompleteResult Done(AccountError error) => new(error, Task.CompletedTask);
}
