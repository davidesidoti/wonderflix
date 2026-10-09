using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli esiti di POST Account/Admin/Test, per canale.</summary>
public static class AccountTestCodes
{
    public const string Ok = "Ok";
    public const string NotConfigured = "NotConfigured";

    /// <summary>Né il contatto dell'admin né uno scritto nella richiesta.</summary>
    public const string NoContact = "NoContact";

    /// <summary>Discord ha rifiutato token o server.</summary>
    public const string Invalid = "Invalid";

    public const string MemberNotFound = "MemberNotFound";
    public const string InvalidTarget = "InvalidTarget";
    public const string DmClosed = "DmClosed";
    public const string SendFailed = "SendFailed";
}

/// <summary>
/// Le funzioni dell'admin sul recupero (spec L §7.4): gli utenti con i loro
/// contatti (email mascherate), lo scollegamento, lo stato dei canali e la
/// prova d'invio. Il codice mandato dall'admin sta in PasswordRecovery.
/// </summary>
public sealed class AccountAdmin(
    IUserDirectory users,
    ContactRegistry contacts,
    CodeBook codes,
    AccountSender sender,
    IDiscordSender discord,
    IAccountSettings settings,
    ILogger<AccountAdmin> logger)
{
    /// <summary>Tutti gli utenti per nome, con i loro contatti.</summary>
    public List<AdminUserDto> Users()
    {
        var all = contacts.All();
        return users.GetUsers()
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u =>
            {
                var mine = all.GetValueOrDefault(u.Id);
                return new AdminUserDto(
                    u.Id.ToString("N"),
                    u.Name,
                    u.IsAdmin,
                    u.Enabled,
                    mine?.Discord is { } discordContact ? new AdminDiscordDto(discordContact.Name) : null,
                    mine?.Email is { } emailContact ? new AdminEmailDto(MaskEmail(emailContact.Address)) : null,
                    mine?.LastReminderAt);
            })
            .ToList();
    }

    /// <summary>
    /// Toglie tutti i contatti di un utente e annulla un codice di recupero
    /// già mandato; UnknownUser se Jellyfin non lo conosce. L'admin che l'ha
    /// fatto finisce nel registro.
    /// </summary>
    public AccountError? Unlink(Guid userId, Guid adminId)
    {
        if (users.GetUser(userId) is null)
        {
            return AccountError.UnknownUser;
        }

        contacts.RemoveAll(userId);

        // Scollegare è lo strumento per "questo contatto è compromesso": annulla anche un codice già mandato lì.
        codes.Discard(userId, CodePurpose.Recovery);
        logger.LogInformation(
            "Contatti di {UserId} scollegati dall'admin {AdminId}", userId.ToString("N"), AdminCaller.Describe(adminId));
        return null;
    }

    /// <summary>I canali e quanti utenti attivi e non admin hanno almeno un contatto raggiungibile.</summary>
    public AccountStatusResponse Status()
    {
        var all = contacts.All();
        var eligible = users.GetUsers().Where(u => u.Enabled && !u.IsAdmin).ToList();

        // Un contatto su un canale spento non serve al recupero: non conta.
        return new AccountStatusResponse(
            Channel(AccountChannel.Discord),
            Channel(AccountChannel.Email),
            eligible.Count(u => all.TryGetValue(u.Id, out var mine) && settings.HasReachableContact(mine)),
            eligible.Count,
            settings.ContactReminderDays);
    }

    /// <summary>
    /// Un messaggio di prova per canale: al nome Discord e all'indirizzo
    /// scritti, oppure ai contatti dell'admin. Discord controlla prima token
    /// e server.
    /// </summary>
    public async Task<AccountTestResponse> TestAsync(
        Guid adminId, string? language, string? discordName, string? email, CancellationToken cancellationToken)
    {
        var mine = contacts.Get(adminId);
        var message = AccountMessages.Test(language);

        // In parallelo: l'attesa è quella del canale più lento, non la somma (l'app aspetta al massimo 30 s).
        var discordTest = TestDiscordAsync(mine, discordName, message, cancellationToken);
        var emailTest = TestEmailAsync(mine, email, message, cancellationToken);
        await Task.WhenAll(discordTest, emailTest).ConfigureAwait(false);
        return new AccountTestResponse(await discordTest.ConfigureAwait(false), await emailTest.ConfigureAwait(false));
    }

    /// <summary>"m•••@example.com": prima lettera, puntini, dominio intero.</summary>
    internal static string MaskEmail(string address)
    {
        var at = address.LastIndexOf('@');
        return at <= 0 ? "•••" : address[..1] + "•••" + address[at..];
    }

    private async Task<string> TestDiscordAsync(
        UserContacts mine, string? name, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return AccountTestCodes.NotConfigured;
        }

        var check = await discord.CheckAsync(cancellationToken).ConfigureAwait(false);
        if (check == DiscordCheck.Invalid)
        {
            sender.RecordInvalid(AccountChannel.Discord);
            return AccountTestCodes.Invalid;
        }

        if (check == DiscordCheck.Failed)
        {
            sender.Record(AccountChannel.Discord, SendOutcome.Failed);
            return AccountTestCodes.SendFailed;
        }

        var target = mine.Discord?.Id;
        if (!string.IsNullOrWhiteSpace(name))
        {
            var cleaned = ContactLinking.CleanDiscordName(name);
            if (cleaned is null)
            {
                return AccountTestCodes.MemberNotFound;
            }

            var lookup = await discord.FindMemberAsync(cleaned, cancellationToken).ConfigureAwait(false);
            if (lookup.Failed)
            {
                return AccountTestCodes.SendFailed;
            }

            if (lookup.Member is null)
            {
                return AccountTestCodes.MemberNotFound;
            }

            target = lookup.Member.Id;
        }

        return target is null
            ? AccountTestCodes.NoContact
            : Outcome(await sender.SendAsync(AccountChannel.Discord, target, message, cancellationToken).ConfigureAwait(false));
    }

    private async Task<string> TestEmailAsync(
        UserContacts mine, string? email, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsEmailConfigured())
        {
            return AccountTestCodes.NotConfigured;
        }

        var target = mine.Email?.Address;
        if (!string.IsNullOrWhiteSpace(email))
        {
            target = ContactLinking.CleanEmail(email);
            if (target is null)
            {
                return AccountTestCodes.InvalidTarget;
            }
        }

        return target is null
            ? AccountTestCodes.NoContact
            : Outcome(await sender.SendAsync(AccountChannel.Email, target, message, cancellationToken).ConfigureAwait(false));
    }

    private static string Outcome(SendOutcome outcome) => outcome switch
    {
        SendOutcome.Sent => AccountTestCodes.Ok,
        SendOutcome.DmClosed => AccountTestCodes.DmClosed,
        _ => AccountTestCodes.SendFailed,
    };

    // Di un canale spento non si mostra l'ultimo errore: è di quando era acceso.
    private ChannelStatusDto Channel(AccountChannel channel)
    {
        var configured = settings.IsConfigured(channel);
        return new ChannelStatusDto(
            configured,
            configured && sender.LastError(channel) is { } error ? new SendErrorDto(error.At, error.Code) : null);
    }
}
