using System.Net.Mail;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Collegare e verificare i contatti di un utente (spec L §7.4): il nome
/// Discord o l'email, un codice mandato lì, il codice scritto nell'app.
/// Nel file entrano solo i contatti verificati. Collegare, cambiare e
/// scollegare un contatto chiede la password attuale dell'account (spec L §8):
/// chi ha solo una sessione aperta non può metterci i propri contatti per
/// prendersi l'account. La conferma no: il codice prova che l'avvio era
/// autorizzato.
/// </summary>
public sealed class ContactLinking(
    ContactRegistry contacts,
    CodeBook codes,
    RateLimiter limiter,
    IDiscordSender discord,
    IPasswordCheck passwords,
    AccountSender sender,
    IAccountSettings settings,
    InboxService inbox,
    TimeProvider time,
    ILogger<ContactLinking> logger)
{
    /// <summary>Lunghezza massima di un indirizzo email.</summary>
    public const int MaxEmailLength = 254;

    // I nomi utente Discord di oggi: da 2 a 32 lettere, cifre, "_" e ".".
    private static readonly Regex DiscordName = new("^[A-Za-z0-9_.]{2,32}$", RegexOptions.CultureInvariant);

    /// <summary>I propri contatti e i canali del server.</summary>
    public ContactsResponse Get(Guid userId)
    {
        var mine = contacts.Get(userId);
        return new ContactsResponse(
            new AccountChannelsDto(settings.IsDiscordConfigured(), settings.IsEmailConfigured()),
            mine.Discord is { } discordContact ? new DiscordContactDto(discordContact.Name, discordContact.VerifiedAt) : null,
            mine.Email is { } emailContact ? new EmailContactDto(emailContact.Address, emailContact.VerifiedAt) : null);
    }

    /// <summary>
    /// Manda il codice per collegare un contatto. Nell'ordine: canale spento,
    /// contatto scritto male, limiti (guardati), password attuale, membro
    /// Discord che non c'è, invio. Un invio non riuscito toglie il codice.
    /// I limiti sono due, con due scopi diversi:
    /// - un codice al minuto per utente e canale: si guarda prima della
    ///   password, ma si conta solo quando il codice sta per essere emesso
    ///   (dopo una ricerca riuscita). Così un nome Discord scritto male non
    ///   fa aspettare un minuto per correggerlo, e Discord ed email non si
    ///   bloccano a vicenda;
    /// - cinque all'ora per utente: si guarda prima della password e si conta
    ///   dopo, quando la password è giusta e sta per partire la ricerca. Ogni
    ///   ricerca conta, quindi nessuno scorre i membri del server a tentativi,
    ///   ma una password sbagliata non consuma l'ora (le password a caso le
    ///   ferma <see cref="LimitTypes.PasswordChecks"/>).
    /// </summary>
    public async Task<AccountResult<LinkStartResponse>> StartAsync(
        Guid userId,
        AccountChannel channel,
        string? target,
        string? password,
        string? language,
        CancellationToken cancellationToken)
    {
        if (userId == Guid.Empty)
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.Invalid);
        }

        if (!settings.IsConfigured(channel))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.ChannelOff);
        }

        var cleaned = channel == AccountChannel.Discord ? CleanDiscordName(target) : CleanEmail(target);
        if (cleaned is null)
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.InvalidTarget);
        }

        var key = userId.ToString("N");
        var minuteKey = $"{key}:{channel.Name()}";
        if (limiter.IsLimited(minuteKey, LimitTypes.LinkStartMinute) || limiter.IsLimited(key, LimitTypes.LinkStartHour))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.RateLimited);
        }

        if (await CheckPasswordAsync(userId, password).ConfigureAwait(false) is { } passwordError)
        {
            return AccountResult<LinkStartResponse>.Fail(passwordError);
        }

        // L'ora si conta qui, con la password giusta e prima della ricerca. Se due richieste
        // arrivano insieme, la seconda trova l'ora già presa.
        if (!limiter.TryAcquire(key, LimitTypes.LinkStartHour))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.RateLimited);
        }

        PendingContact pending;
        if (channel == AccountChannel.Discord)
        {
            var lookup = await discord.FindMemberAsync(cleaned, cancellationToken).ConfigureAwait(false);
            if (lookup.Failed)
            {
                sender.Record(AccountChannel.Discord, SendOutcome.Failed);
                return AccountResult<LinkStartResponse>.Fail(AccountError.SendFailed);
            }

            if (lookup.Member is null)
            {
                return AccountResult<LinkStartResponse>.Fail(AccountError.MemberNotFound);
            }

            // ContactRegistry rifiuta un Discord senza id valido o senza nome, ma alla conferma,
            // con il codice già usato. Un membro così (risposta strana di Discord) si ferma qui,
            // prima di emettere il codice, come un invio fallito.
            if (!DiscordIds.IsSnowflake(lookup.Member.Id) || string.IsNullOrWhiteSpace(lookup.Member.Username))
            {
                sender.Record(AccountChannel.Discord, SendOutcome.Failed);
                return AccountResult<LinkStartResponse>.Fail(AccountError.SendFailed);
            }

            pending = new PendingContact(lookup.Member.Id, lookup.Member.Username);
        }
        else
        {
            pending = new PendingContact(cleaned, null);
        }

        // Il minuto si conta qui, con il codice che sta per partire. Se due richieste
        // arrivano insieme, la seconda trova il minuto già preso.
        if (!limiter.TryAcquire(minuteKey, LimitTypes.LinkStartMinute))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.RateLimited);
        }

        var purpose = PurposeFor(channel);
        var (code, expiresAt) = codes.Issue(userId, purpose, pending);
        var outcome = await sender.SendAsync(channel, pending.Value, AccountMessages.Verify(language, code), cancellationToken)
            .ConfigureAwait(false);
        if (outcome != SendOutcome.Sent)
        {
            codes.Discard(userId, purpose);
            return AccountResult<LinkStartResponse>.Fail(
                outcome == SendOutcome.DmClosed ? AccountError.DmClosed : AccountError.SendFailed);
        }

        logger.LogInformation("Codice per collegare {Channel} mandato all'utente {UserId}", channel, userId);
        return AccountResult<LinkStartResponse>.Ok(new LinkStartResponse(expiresAt));
    }

    /// <summary>Con il codice giusto il contatto è verificato e i promemoria spariscono.</summary>
    public async Task<AccountResult<ContactsResponse>> ConfirmAsync(Guid userId, AccountChannel channel, string? code)
    {
        var check = codes.Check(userId, PurposeFor(channel), code);
        if (!check.Ok || check.Pending is null)
        {
            return AccountResult<ContactsResponse>.Fail(AccountError.InvalidCode);
        }

        var now = time.GetUtcNow();
        if (channel == AccountChannel.Discord)
        {
            contacts.SetDiscord(userId, new DiscordContact
            {
                Id = check.Pending.Value,
                Name = check.Pending.Name ?? string.Empty,
                VerifiedAt = now,
            });
        }
        else
        {
            contacts.SetEmail(userId, new EmailContact { Address = check.Pending.Value, VerifiedAt = now });
        }

        await inbox.RemoveContactRemindersAsync(userId).ConfigureAwait(false);
        logger.LogInformation("{Channel} collegato all'utente {UserId}", channel, userId);
        return AccountResult<ContactsResponse>.Ok(Get(userId));
    }

    /// <summary>
    /// Toglie il contatto di un canale, se la password attuale è giusta;
    /// niente errore anche se il contatto non c'era. Annulla anche un codice
    /// di recupero già mandato.
    /// </summary>
    public async Task<AccountError?> UnlinkAsync(Guid userId, AccountChannel channel, string? password)
    {
        if (userId == Guid.Empty)
        {
            return AccountError.Invalid;
        }

        if (await CheckPasswordAsync(userId, password).ConfigureAwait(false) is { } passwordError)
        {
            return passwordError;
        }

        // Scollegare è lo strumento per "questo contatto è compromesso", quindi annulla anche un codice
        // di recupero già mandato lì (anche se il contatto non c'era: la password è giusta, la richiesta è del proprietario).
        codes.Discard(userId, CodePurpose.Recovery);

        if (contacts.Remove(userId, channel))
        {
            logger.LogInformation("{Channel} scollegato dall'utente {UserId}", channel, userId);
        }

        return null;
    }

    /// <summary>Il nome Discord senza spazi ai lati né "@" iniziale; null se non sembra un nome Discord.</summary>
    internal static string? CleanDiscordName(string? raw)
    {
        var name = raw?.Trim().TrimStart('@');
        return name is not null && DiscordName.IsMatch(name) ? name : null;
    }

    /// <summary>
    /// Solo l'indirizzo, com'è scritto: ASCII, senza parentesi quadre (niente
    /// indirizzi IP), con un dominio di almeno due etichette non vuote che non
    /// iniziano né finiscono con "-"; null altrimenti.
    /// </summary>
    internal static string? CleanEmail(string? raw)
    {
        var address = raw?.Trim();
        if (string.IsNullOrEmpty(address)
            || address.Length > MaxEmailLength
            || !address.All(char.IsAscii)
            || address.Contains('[', StringComparison.Ordinal)
            || address.Contains(']', StringComparison.Ordinal))
        {
            return null;
        }

        if (!MailAddress.TryCreate(address, out var parsed)
            || parsed.Address != address
            || !string.IsNullOrEmpty(parsed.DisplayName))
        {
            return null;
        }

        var labels = address[(address.LastIndexOf('@') + 1)..].Split('.');
        return labels.Length >= 2 && labels.All(label => label.Length > 0 && label[0] != '-' && label[^1] != '-')
            ? address
            : null;
    }

    // Dieci controlli all'ora per utente: chi ha la sessione non può provare password all'infinito.
    // Un account senza password ha la password vuota, quindi niente (null) vale come "".
    private async Task<AccountError?> CheckPasswordAsync(Guid userId, string? password)
    {
        if (!limiter.TryAcquire(userId.ToString("N"), LimitTypes.PasswordChecks))
        {
            return AccountError.RateLimited;
        }

        return await passwords.IsCurrentPasswordAsync(userId, password ?? string.Empty).ConfigureAwait(false)
            ? null
            : AccountError.WrongPassword;
    }

    private static CodePurpose PurposeFor(AccountChannel channel) =>
        channel == AccountChannel.Discord ? CodePurpose.VerifyDiscord : CodePurpose.VerifyEmail;
}
