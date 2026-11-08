using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountAdminTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;

    // Chi chiama le funzioni dell'admin (un admin qualsiasi: conta solo che finisca nel log).
    private static readonly Guid AdminId = Guid.NewGuid();
    private readonly AccountRig _rig = new();
    private readonly AccountAdmin _admin;

    public AccountAdminTests() => _admin = _rig.Admin();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public void UsersAreListedByNameWithMaskedEmails()
    {
        var mario = _rig.UserWithContacts("mario");
        _rig.Server.AddUser("Peach", isAdmin: true);
        var bowser = _rig.Server.AddUser("Bowser", enabled: false);
        _rig.Contacts.MarkReminded(bowser.Id, _rig.Time.GetUtcNow());

        var users = _admin.Users();

        Assert.Equal(new[] { "Bowser", "mario", "Peach" }, users.Select(u => u.Name));
        Assert.Equal(
            new AdminUserDto(bowser.Id.ToString("N"), "Bowser", false, false, null, null, _rig.Time.GetUtcNow()),
            users[0]);
        Assert.Equal(mario.Id.ToString("N"), users[1].Id);
        Assert.Equal(new AdminDiscordDto("mario"), users[1].Discord);
        Assert.Equal(new AdminEmailDto("m•••@example.com"), users[1].Email);
        Assert.True(users[2].IsAdmin);
    }

    [Theory]
    [InlineData("mario@example.com", "m•••@example.com")]
    [InlineData("a@b.it", "a•••@b.it")]
    [InlineData("strano", "•••")]
    [InlineData("@example.com", "•••")]
    public void EmailsAreMasked(string address, string masked) =>
        Assert.Equal(masked, AccountAdmin.MaskEmail(address));

    [Fact]
    public void UnlinkRemovesEveryContactOfAKnownUser()
    {
        var mario = _rig.UserWithContacts("Mario");

        Assert.Equal(AccountError.UnknownUser, _admin.Unlink(Guid.NewGuid(), AdminId));
        Assert.Null(_admin.Unlink(mario.Id, AdminId));
        Assert.False(_rig.Contacts.Get(mario.Id).HasContact);
    }

    // Scollegare è lo strumento per "questo contatto è compromesso": un codice di recupero già mandato lì non deve più valere.
    [Fact]
    public async Task UnlinkCancelsAPendingRecoveryCode()
    {
        var mario = _rig.UserWithContacts("Mario");
        var (code, _) = _rig.Codes.Issue(mario.Id, CodePurpose.Recovery);

        Assert.Null(_admin.Unlink(mario.Id, AdminId));

        Assert.Equal(0, _rig.Codes.Count);
        Assert.Equal(AccountError.InvalidCode, (await _rig.Recovery().CompleteAsync("mario", code, "nuova-password", "it")).Error);
        Assert.Empty(_rig.Passwords.Calls);
    }

    // Un contatto compromesso non si ricollega con un codice già partito: lo scollegamento annulla anche quelli di verifica.
    [Fact]
    public async Task UnlinkCancelsThePendingLinkCodesToo()
    {
        var mario = _rig.UserWithContacts("Mario");
        var (discordCode, _) = _rig.Codes.Issue(mario.Id, CodePurpose.VerifyDiscord, new PendingContact("333333333333333333", "intruso"));
        var (emailCode, _) = _rig.Codes.Issue(mario.Id, CodePurpose.VerifyEmail, new PendingContact("intruso@example.com", null));
        _rig.Codes.Issue(mario.Id, CodePurpose.Recovery);
        _rig.Codes.Issue(Guid.NewGuid(), CodePurpose.VerifyEmail, new PendingContact("altro@example.com", null));

        Assert.Null(_admin.Unlink(mario.Id, AdminId));

        // Resta solo il codice di un altro utente.
        Assert.Equal(1, _rig.Codes.Count);
        var linking = _rig.Linking();
        Assert.Equal(AccountError.InvalidCode, (await linking.ConfirmAsync(mario.Id, AccountChannel.Discord, discordCode)).Error);
        Assert.Equal(AccountError.InvalidCode, (await linking.ConfirmAsync(mario.Id, AccountChannel.Email, emailCode)).Error);
        Assert.False(_rig.Contacts.Get(mario.Id).HasContact);
    }

    [Fact]
    public void AnUnknownUserLeavesTheCodesAlone()
    {
        _rig.Codes.Issue(Guid.NewGuid(), CodePurpose.Recovery);

        Assert.Equal(AccountError.UnknownUser, _admin.Unlink(Guid.NewGuid(), AdminId));

        Assert.Equal(1, _rig.Codes.Count);
    }

    [Fact]
    public void UnlinkIsInTheLogWithTheAdmin()
    {
        var mario = _rig.UserWithContacts("Mario");
        var logger = new RecordingLogger<AccountAdmin>();
        var admin = new AccountAdmin(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Sender, _rig.Discord, _rig.Settings, _rig.Inbox, _rig.Time, logger);

        Assert.Equal(AccountError.UnknownUser, admin.Unlink(Guid.NewGuid(), AdminId));
        Assert.Empty(logger.Entries);
        Assert.Null(admin.Unlink(mario.Id, AdminId));

        var entry = Assert.Single(logger.Entries);
        Assert.Equal(LogLevel.Information, entry.Level);
        Assert.Equal($"Contatti di {mario.Id:N} scollegati dall'admin {AdminId:N}", entry.Message);
    }

    [Fact]
    public void TheCallerIsDescribedForTheLog()
    {
        Assert.Equal("chiave API", AdminCaller.Describe(Guid.Empty));
        Assert.Equal(AdminId.ToString("N"), AdminCaller.Describe(AdminId));
    }

    // Con una chiave API non c'è un utente (id tutto a zero): nel registro si legge "chiave API", non zeri.
    [Fact]
    public void UnlinkWithAnApiKeyIsInTheLogAsSuch()
    {
        var mario = _rig.UserWithContacts("Mario");
        var logger = new RecordingLogger<AccountAdmin>();
        var admin = new AccountAdmin(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Sender, _rig.Discord, _rig.Settings, _rig.Inbox, _rig.Time, logger);

        Assert.Null(admin.Unlink(mario.Id, Guid.Empty));

        var entry = Assert.Single(logger.Entries);
        Assert.Equal($"Contatti di {mario.Id:N} scollegati dall'admin chiave API", entry.Message);
        Assert.DoesNotContain("00000000", entry.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StatusCountsActiveNonAdminUsersAndShowsTheLastErrors()
    {
        _rig.UserWithContacts("Mario");
        _rig.Server.AddUser("Luigi");
        _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.UserWithContacts("Daisy", enabled: false);
        _rig.Settings.ContactReminderDays = 7;
        _rig.Discord.Outcomes["999999999999999999"] = SendOutcome.DmClosed;
        await _rig.Sender.SendAsync(AccountChannel.Discord, "999999999999999999", AccountMessages.Test("it"), Ct);
        _rig.Settings.SmtpHost = string.Empty;

        var status = _admin.Status();

        Assert.Equal(new ChannelStatusDto(true, new SendErrorDto(_rig.Time.GetUtcNow(), "DmClosed")), status.Discord);
        Assert.Equal(new ChannelStatusDto(false, null), status.Email);
        Assert.Equal(1, status.WithContacts);
        Assert.Equal(2, status.Users);
        Assert.Equal(7, status.ReminderDays);
    }

    // Un contatto su un canale spento non serve al recupero: chi ha solo quello non è raggiungibile.
    [Fact]
    public void StatusDoesNotCountContactsOnAChannelThatIsOff()
    {
        _rig.UserWithContacts("Mario");
        var luigi = _rig.Server.AddUser("Luigi");
        _rig.Contacts.SetEmail(luigi.Id, new EmailContact { Address = "luigi@example.com", VerifiedAt = _rig.Time.GetUtcNow() });
        var peach = _rig.Server.AddUser("Peach");
        _rig.Contacts.SetDiscord(peach.Id, new DiscordContact { Id = "333333333333333333", Name = "peach", VerifiedAt = _rig.Time.GetUtcNow() });
        Assert.Equal(3, _admin.Status().WithContacts);

        _rig.Settings.SmtpHost = string.Empty;

        // Mario ha ancora Discord; Luigi aveva solo l'email.
        var status = _admin.Status();
        Assert.Equal(2, status.WithContacts);
        Assert.Equal(3, status.Users);

        _rig.Settings.DiscordBotToken = string.Empty;
        Assert.Equal(0, _admin.Status().WithContacts);
    }

    [Fact]
    public async Task TheTestGoesToTheAdminsOwnContacts()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);

        Assert.Equal(new AccountTestResponse("Ok", "Ok"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));

        Assert.Contains("Messaggio di prova", _rig.Discord.Sent.Single().Text);
        Assert.Equal("peach@example.com", _rig.Mail.Sent.Single().To);
    }

    [Fact]
    public async Task WithoutContactsTheTestStillChecksDiscord()
    {
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), await _admin.TestAsync(Guid.Empty, "it", null, " ", Ct));

        _rig.Discord.Check = DiscordCheck.Invalid;
        Assert.Equal("Invalid", (await _admin.TestAsync(Guid.Empty, "it", null, null, Ct)).Discord);
        Assert.Equal("Invalid", _rig.Sender.LastError(AccountChannel.Discord)!.Code);

        _rig.Discord.Check = DiscordCheck.Failed;
        Assert.Equal("SendFailed", (await _admin.TestAsync(Guid.Empty, "it", null, null, Ct)).Discord);
    }

    [Fact]
    public async Task TheTestCanGoToANameAndAnAddress()
    {
        _rig.Discord.Members["davide"] = new DiscordMember("444444444444444444", "davide");

        Assert.Equal(
            new AccountTestResponse("Ok", "Ok"),
            await _admin.TestAsync(Guid.Empty, "en", "@Davide", "davide@example.com", Ct));

        Assert.Equal("444444444444444444", _rig.Discord.Sent.Single().UserId);
        Assert.Equal("WonderFlix — test", _rig.Mail.Sent.Single().Message.Subject);
        Assert.Equal(
            new AccountTestResponse("MemberNotFound", "InvalidTarget"),
            await _admin.TestAsync(Guid.Empty, "it", "luigi", "luigi", Ct));
        // Un nome scritto male non è un nome Discord (come l'email non valida): niente ricerca, niente errore del canale.
        Assert.Equal("InvalidTarget", (await _admin.TestAsync(Guid.Empty, "it", "nome con spazi", null, Ct)).Discord);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Discord));

        // Una ricerca che fallisce è un errore del canale, come quando si collega un contatto.
        _rig.Discord.SearchFails = true;
        Assert.Equal("SendFailed", (await _admin.TestAsync(Guid.Empty, "it", "davide", null, Ct)).Discord);
        Assert.Equal("SendFailed", _rig.Sender.LastError(AccountChannel.Discord)!.Code);
    }

    [Fact]
    public async Task TheTestSaysWhatWentWrong()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.Discord.Outcomes[_rig.Contacts.Get(peach.Id).Discord!.Id] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["peach@example.com"] = SendOutcome.Failed;

        Assert.Equal(new AccountTestResponse("DmClosed", "SendFailed"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));

        _rig.Settings.DiscordBotToken = string.Empty;
        _rig.Settings.MailFrom = string.Empty;
        Assert.Equal(new AccountTestResponse("NotConfigured", "NotConfigured"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));
    }
    [Fact]
    public async Task LookupFindsTheMember()
    {
        var member = new DiscordMember("444444444444444444", "mario", "Mario Rossi");
        _rig.Discord.Members["Mario"] = member;

        var result = await _admin.LookupDiscordAsync(" @Mario ", Ct);

        Assert.Null(result.Error);
        Assert.Equal(member, result.Value);
        Assert.Equal("Mario", Assert.Single(_rig.Discord.Searches));
    }

    [Fact]
    public async Task LookupWithDiscordOffIsChannelOff()
    {
        _rig.Settings.DiscordBotToken = string.Empty;

        Assert.Equal(AccountError.ChannelOff, (await _admin.LookupDiscordAsync("mario", Ct)).Error);
        Assert.Empty(_rig.Discord.Searches);
    }

    [Fact]
    public async Task LookupOfABadNameIsInvalidTarget()
    {
        Assert.Equal(AccountError.InvalidTarget, (await _admin.LookupDiscordAsync("a", Ct)).Error);
        Assert.Equal(AccountError.InvalidTarget, (await _admin.LookupDiscordAsync(null, Ct)).Error);
        Assert.Empty(_rig.Discord.Searches);
    }

    [Fact]
    public async Task LookupOfAMissingMemberIsMemberNotFound() =>
        Assert.Equal(AccountError.MemberNotFound, (await _admin.LookupDiscordAsync("luigi", Ct)).Error);

    [Fact]
    public async Task AFailedLookupIsSendFailedAndRecorded()
    {
        _rig.Discord.SearchFails = true;

        Assert.Equal(AccountError.SendFailed, (await _admin.LookupDiscordAsync("mario", Ct)).Error);
        Assert.NotNull(_rig.Sender.LastError(AccountChannel.Discord));
    }

    [Fact]
    public async Task SetDiscordSavesAVerifiedContact()
    {
        var mario = _rig.Server.AddUser("Mario");

        Assert.Null(await _admin.SetDiscordAsync(mario.Id, "444444444444444444", " mario ", AdminId));

        var saved = _rig.Contacts.Get(mario.Id).Discord!;
        Assert.Equal("444444444444444444", saved.Id);
        Assert.Equal("mario", saved.Name);
        Assert.Equal(_rig.Time.GetUtcNow(), saved.VerifiedAt);
    }

    [Fact]
    public async Task SetDiscordReplacesTheContactAndCancelsTheCodes()
    {
        var mario = _rig.UserWithContacts("Mario");
        var (recovery, _) = _rig.Codes.Issue(mario.Id, CodePurpose.Recovery);
        var (verify, _) = _rig.Codes.Issue(mario.Id, CodePurpose.VerifyDiscord, new PendingContact("333333333333333333", "intruso"));

        Assert.Null(await _admin.SetDiscordAsync(mario.Id, "444444444444444444", "nuovo", AdminId));

        Assert.Equal("444444444444444444", _rig.Contacts.Get(mario.Id).Discord!.Id);
        Assert.Equal("nuovo", _rig.Contacts.Get(mario.Id).Discord!.Name);
        Assert.False(_rig.Codes.Check(mario.Id, CodePurpose.Recovery, recovery).Ok);
        Assert.False(_rig.Codes.Check(mario.Id, CodePurpose.VerifyDiscord, verify).Ok);
    }

    [Fact]
    public async Task SetDiscordRemovesTheContactReminders()
    {
        var mario = _rig.Server.AddUser("Mario");
        await _rig.Inbox.AddContactReminderAsync(mario.Id, ["Discord", "Email"]);

        await _admin.SetDiscordAsync(mario.Id, "444444444444444444", "mario", AdminId);

        Assert.Empty(_rig.Inbox.Get(mario.Id).Entries);
    }

    [Fact]
    public async Task SetDiscordErrorsLeaveTheContactAlone()
    {
        var mario = _rig.UserWithContacts("Mario");
        var before = _rig.Contacts.Get(mario.Id).Discord!;

        Assert.Equal(AccountError.UnknownUser, await _admin.SetDiscordAsync(Guid.NewGuid(), "444444444444444444", "x", AdminId));
        Assert.Equal(AccountError.InvalidTarget, await _admin.SetDiscordAsync(mario.Id, "123", "nuovo", AdminId));
        Assert.Equal(AccountError.InvalidTarget, await _admin.SetDiscordAsync(mario.Id, "444444444444444444", " ", AdminId));
        Assert.Equal(AccountError.InvalidTarget, await _admin.SetDiscordAsync(mario.Id, null, "nuovo", AdminId));
        _rig.Settings.DiscordBotToken = string.Empty;
        Assert.Equal(AccountError.ChannelOff, await _admin.SetDiscordAsync(mario.Id, "444444444444444444", "nuovo", AdminId));

        Assert.Equal(before.Id, _rig.Contacts.Get(mario.Id).Discord!.Id);
        Assert.Equal(before.Name, _rig.Contacts.Get(mario.Id).Discord!.Name);
    }

    [Fact]
    public async Task SetEmailSavesAVerifiedContact()
    {
        var mario = _rig.Server.AddUser("Mario");

        Assert.Null(await _admin.SetEmailAsync(mario.Id, " Nuovo@Example.com ", AdminId));

        var saved = _rig.Contacts.Get(mario.Id).Email!;
        Assert.Equal(ContactLinking.CleanEmail(" Nuovo@Example.com "), saved.Address);
        Assert.Equal(_rig.Time.GetUtcNow(), saved.VerifiedAt);
    }

    [Fact]
    public async Task SetEmailErrorsLeaveTheContactAlone()
    {
        var mario = _rig.UserWithContacts("Mario");

        Assert.Equal(AccountError.UnknownUser, await _admin.SetEmailAsync(Guid.NewGuid(), "nuovo@example.com", AdminId));
        Assert.Equal(AccountError.InvalidTarget, await _admin.SetEmailAsync(mario.Id, "non-email", AdminId));
        _rig.Settings.SmtpHost = string.Empty;
        Assert.Equal(AccountError.ChannelOff, await _admin.SetEmailAsync(mario.Id, "nuovo@example.com", AdminId));

        Assert.Equal("mario@example.com", _rig.Contacts.Get(mario.Id).Email!.Address);
    }

    [Fact]
    public async Task SetEmailCancelsTheRecoveryAndTheVerifyCodes()
    {
        var mario = _rig.UserWithContacts("Mario");
        var (recovery, _) = _rig.Codes.Issue(mario.Id, CodePurpose.Recovery);
        var (verify, _) = _rig.Codes.Issue(mario.Id, CodePurpose.VerifyEmail, new PendingContact("intruso@example.com", null));

        Assert.Null(await _admin.SetEmailAsync(mario.Id, "nuovo@example.com", AdminId));

        Assert.Equal("nuovo@example.com", _rig.Contacts.Get(mario.Id).Email!.Address);
        Assert.False(_rig.Codes.Check(mario.Id, CodePurpose.Recovery, recovery).Ok);
        Assert.False(_rig.Codes.Check(mario.Id, CodePurpose.VerifyEmail, verify).Ok);
    }

    [Fact]
    public async Task SettingAContactIsInTheLogWithTheAdminButWithoutTheContact()
    {
        var mario = _rig.Server.AddUser("Mario");
        var logger = new RecordingLogger<AccountAdmin>();
        var admin = new AccountAdmin(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Sender, _rig.Discord, _rig.Settings, _rig.Inbox, _rig.Time, logger);

        Assert.Null(await admin.SetDiscordAsync(mario.Id, "444444444444444444", "mario-segreto", AdminId));
        Assert.Null(await admin.SetEmailAsync(mario.Id, "segreto@example.com", AdminId));

        Assert.Equal(2, logger.Entries.Count);
        foreach (var entry in logger.Entries)
        {
            Assert.Equal(LogLevel.Information, entry.Level);
            Assert.Contains(mario.Id.ToString("N"), entry.Message, StringComparison.Ordinal);
            Assert.Contains(AdminId.ToString("N"), entry.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("segreto", entry.Message, StringComparison.Ordinal);
        }
    }
}
