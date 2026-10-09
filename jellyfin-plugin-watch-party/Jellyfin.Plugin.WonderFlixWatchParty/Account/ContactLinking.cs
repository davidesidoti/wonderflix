using System.Net.Mail;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Collegare e verificare i contatti di un utente (spec L §7.4): il nome
/// Discord o l'email, un codice mandato lì, il codice scritto nell'app.
/// Nel file entrano solo i contatti verificati.
/// </summary>
public sealed class ContactLinking(
    ContactRegistry contacts,
    CodeBook codes,
    RateLimiter limiter,
    IDiscordSender discord,
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
    /// contatto scritto male, limiti, membro Discord che non c'è, invio.
    /// Un invio non riuscito toglie il codice.
    /// </summary>
    public async Task<AccountResult<LinkStartResponse>> StartAsync(
        Guid userId, AccountChannel channel, string? target, string? language, CancellationToken cancellationToken)
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
        if (!limiter.TryAcquire(key, LimitTypes.LinkStartMinute) || !limiter.TryAcquire(key, LimitTypes.LinkStartHour))
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

            pending = new PendingContact(lookup.Member.Id, lookup.Member.Username);
        }
        else
        {
            pending = new PendingContact(cleaned, null);
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

    /// <summary>Toglie il contatto di un canale.</summary>
    public void Unlink(Guid userId, AccountChannel channel) => contacts.Remove(userId, channel);

    /// <summary>Il nome Discord senza spazi ai lati né "@" iniziale; null se non sembra un nome Discord.</summary>
    internal static string? CleanDiscordName(string? raw)
    {
        var name = raw?.Trim().TrimStart('@');
        return name is not null && DiscordName.IsMatch(name) ? name : null;
    }

    /// <summary>Solo l'indirizzo, com'è scritto, con un dominio che ha un punto; null altrimenti.</summary>
    internal static string? CleanEmail(string? raw)
    {
        var address = raw?.Trim();
        if (string.IsNullOrEmpty(address) || address.Length > MaxEmailLength)
        {
            return null;
        }

        if (!MailAddress.TryCreate(address, out var parsed)
            || parsed.Address != address
            || !string.IsNullOrEmpty(parsed.DisplayName))
        {
            return null;
        }

        var domain = address[(address.LastIndexOf('@') + 1)..];
        return domain.Contains('.', StringComparison.Ordinal) && !domain.StartsWith('.') && !domain.EndsWith('.')
            ? address
            : null;
    }

    private static CodePurpose PurposeFor(AccountChannel channel) =>
        channel == AccountChannel.Discord ? CodePurpose.VerifyDiscord : CodePurpose.VerifyEmail;
}
