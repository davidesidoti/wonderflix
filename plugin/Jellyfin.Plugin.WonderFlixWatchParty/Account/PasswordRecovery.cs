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

    // I limiti si guardano e si contano sotto un lucchetto: due richieste insieme non devono
    // passare tutte e due il controllo prima che la prima abbia contato. Uno per Start e uno
    // per CompleteAsync, che toccano limiti diversi.
    private readonly Lock _startLock = new();
    private readonly Lock _completeLock = new();

    /// <summary>
    /// Chiede un codice. Risponde subito, uguale per tutti (tranne i limiti,
    /// che contano il nome scritto, esista o no). Dopo, in background: se
    /// l'utente può usare il recupero e ha contatti, il codice va a tutti.
    /// I limiti si guardano tutti prima: una richiesta rifiutata non ne
    /// consuma nessuno (altrimenti chi insiste su un nome già fermato
    /// svuoterebbe il limite di tutti).
    /// </summary>
    public RecoveryStartResult Start(string? username, string? language)
    {
        var name = Trimmed(username);
        if (name is null)
        {
            return new RecoveryStartResult(AccountError.Invalid, Task.CompletedTask);
        }

        var key = Key(name);
        lock (_startLock)
        {
            if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryStartGlobal)
                || limiter.IsLimited(key, LimitTypes.RecoveryStartMinute)
                || limiter.IsLimited(key, LimitTypes.RecoveryStartHour)
                || limiter.IsLimited(key, LimitTypes.RecoveryStartDay))
            {
                return new RecoveryStartResult(AccountError.RateLimited, Task.CompletedTask);
            }

            // Sotto il lucchetto, dopo il controllo, nessuno di questi può fallire.
            limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryStartGlobal);
            limiter.TryAcquire(key, LimitTypes.RecoveryStartMinute);
            limiter.TryAcquire(key, LimitTypes.RecoveryStartHour);
            limiter.TryAcquire(key, LimitTypes.RecoveryStartDay);
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

        // Tutto fino al cambio è sincrono e sta sotto un solo lucchetto (vedi Verify).
        var verdict = Verify(name, code, newPassword);
        if (verdict is not { Error: null, User: { } user, Password: { } password })
        {
            return Done(verdict.Error ?? AccountError.InvalidCode);
        }

        try
        {
            await passwords.ResetAsync(user.Id, password).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Password di {UserId} non cambiata", user.Id.ToString("N"));
            throw;
        }

        logger.LogInformation("Password di {UserId} cambiata con il codice di recupero", user.Id.ToString("N"));

        // L'avviso non trattiene la risposta.
        return new RecoveryCompleteResult(null, Task.Run(() => NotifyChangedAsync(user, language)));
    }

    /// <summary>
    /// Il codice mandato dall'admin (spec L §7.4): la risposta dice com'è
    /// andata, e non ci sono i limiti del recupero. L'admin che l'ha chiesto
    /// finisce nel registro.
    /// </summary>
    public async Task<AccountResult<AdminRecoveryResponse>> SendForAdminAsync(
        Guid userId, Guid adminId, string? language, CancellationToken cancellationToken)
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

        logger.LogInformation(
            "Codice di recupero di {UserId} mandato dall'admin {AdminId} su {Count} canali",
            userId.ToString("N"),
            AdminCaller.Describe(adminId),
            sent.Count);
        return AccountResult<AdminRecoveryResponse>.Ok(new AdminRecoveryResponse(sent.Select(c => c.Name()).ToList()));
    }

    // Il risultato di Verify: l'utente e la password da mettergli (già controllata), oppure l'errore.
    private sealed record Verdict(UserRef? User, string? Password, AccountError? Error);

    // La parte di CompleteAsync prima del cambio: limiti, lunghezza della password, utente, codice,
    // e il conteggio degli errori. È sincrona e sta sotto un solo lucchetto, così richieste insieme
    // non possono superare i limiti (guardare e contare in due momenti lasciava passare chi arrivava
    // nello stesso istante). Il codice giusto vale una volta (CodeBook), quindi il cambio può stare fuori.
    private Verdict Verify(string name, string? code, string? newPassword)
    {
        var key = Key(name);
        lock (_completeLock)
        {
            if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal)
                || limiter.IsLimited(key, LimitTypes.RecoveryFail)
                || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
            {
                return new Verdict(null, null, AccountError.RateLimited);
            }

            if (newPassword is null || newPassword.Length < MinPasswordLength || newPassword.Length > MaxPasswordLength)
            {
                return new Verdict(null, null, AccountError.WeakPassword);
            }

            var match = Find(name);
            var user = match is { Enabled: true, IsAdmin: false } ? match : null;
            if (user is not null && codes.Check(user.Id, CodePurpose.Recovery, code).Ok)
            {
                return new Verdict(user, newPassword, null);
            }

            limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryFailGlobal);
            limiter.TryAcquire(key, LimitTypes.RecoveryFail);
            limiter.TryAcquire(key, LimitTypes.RecoveryFailDay);

            // Nel log si vede quando qualcuno prova a indovinare i codici: una volta sola,
            // quando il limite scatta (dopo si risponde 429 prima di arrivare qui). Il registro
            // è solo del server, quindi dice di chi è il nome anche se è un admin o un utente
            // disattivato (per loro il recupero non vale, ma il nome è comunque di un utente).
            // Mai il testo scritto: potrebbe essere un'email o contenere a capo.
            if (limiter.IsLimited(key, LimitTypes.RecoveryFail) || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
            {
                logger.LogWarning(
                    "Recupero della password fermato dai limiti per {Who}",
                    match?.Id.ToString("N") ?? "un nome che non è un utente");
            }

            if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal))
            {
                logger.LogWarning("Recupero della password fermato per tutti: troppi codici sbagliati oggi");
            }

            return new Verdict(null, null, AccountError.InvalidCode);
        }
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
                logger.LogWarning("Codice di recupero di {UserId} non mandato: nessun canale ha funzionato", user.Id.ToString("N"));
                return;
            }

            logger.LogInformation("Codice di recupero di {UserId} mandato su {Count} canali", user.Id.ToString("N"), sent.Count);
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
            logger.LogWarning(ex, "Avviso del cambio password non mandato a {UserId}", user.Id.ToString("N"));
        }
    }

    // L'utente con questo nome, qualunque sia: il nome senza maiuscole, come Jellyfin.
    private UserRef? Find(string name) =>
        users.GetUsers().FirstOrDefault(u => string.Equals(u.Name, name, StringComparison.OrdinalIgnoreCase));

    // L'utente può usare il recupero: esiste, è attivo e non è admin.
    private UserRef? Eligible(string name) => Find(name) is { Enabled: true, IsAdmin: false } user ? user : null;

    private static string? Trimmed(string? raw)
    {
        var name = raw?.Trim();
        return string.IsNullOrEmpty(name) || name.Length > MaxUsernameLength ? null : name;
    }

    // Maiuscolo e non minuscolo: Jellyfin trova l'utente con OrdinalIgnoreCase, che confronta le maiuscole, e
    // ToLowerInvariant tiene diverse lettere che per quel confronto sono uguali (il sigma finale e quello normale).
    // Con due chiavi per lo stesso utente il limite del nome si aggirerebbe scrivendolo in un altro modo.
    private static string Key(string name) => name.ToUpperInvariant();

    private static RecoveryCompleteResult Done(AccountError error) => new(error, Task.CompletedTask);
}
