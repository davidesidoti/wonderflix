using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactLinkingTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly AccountRig _rig = new();
    private readonly ContactLinking _linking;
    private readonly UserRef _mario;

    public ContactLinkingTests()
    {
        _mario = _rig.Server.AddUser("Mario");
        _rig.Discord.Members["mario"] = new DiscordMember("222222222222222222", "mario");
        _linking = _rig.Linking();
    }

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task DiscordIsLinkedWithTheCodeSentByDirectMessage()
    {
        var start = await _linking.StartAsync(_mario.Id, AccountChannel.Discord, " @Mario ", "giusta", "it", Ct);

        Assert.Null(start.Error);
        Assert.Equal(_rig.Time.GetUtcNow() + CodeBook.Lifetime, start.Value!.ExpiresAt);
        Assert.Equal(new[] { "Mario" }, _rig.Discord.Searches);
        Assert.Contains("collegare questo account", _rig.Discord.Sent.Single().Text);
        var code = _rig.Discord.LastCode("222222222222222222");

        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code);

        Assert.Null(confirm.Error);
        Assert.Equal(new DiscordContactDto("mario", _rig.Time.GetUtcNow()), confirm.Value!.Discord);
        Assert.Null(confirm.Value.Email);
        Assert.Equal("222222222222222222", _rig.Contacts.Get(_mario.Id).Discord!.Id);
        // Il codice vale una volta.
        Assert.Equal(AccountError.InvalidCode, (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code)).Error);
    }

    [Fact]
    public async Task TheEmailIsLinkedAsWritten()
    {
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, " Mario@Example.com ", "giusta", "en", Ct)).Error);

        var sent = Assert.Single(_rig.Mail.Sent);
        Assert.Equal("Mario@Example.com", sent.To);
        Assert.Equal("WonderFlix — code", sent.Message.Subject);
        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, _rig.Mail.LastCode("Mario@Example.com"));
        Assert.Equal("Mario@Example.com", confirm.Value!.Email!.Address);
    }

    [Fact]
    public async Task AWrongCodeIsInvalidAndTheChannelsAreSeparate()
    {
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct);
        var code = _rig.Mail.LastCode("mario@example.com");

        Assert.Equal(AccountError.InvalidCode, (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code)).Error);
        Assert.Equal(
            AccountError.InvalidCode,
            (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, code == "000000" ? "111111" : "000000")).Error);
        Assert.Null((await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, code)).Error);
    }

    [Fact]
    public async Task AChannelThatIsOffComesFirst()
    {
        _rig.Settings.DiscordBotToken = string.Empty;

        Assert.Equal(AccountError.ChannelOff, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "x", "giusta", "it", Ct)).Error);

        Assert.Empty(_rig.Discord.Searches);
        Assert.False(_linking.Get(_mario.Id).Channels.Discord);
        Assert.True(_linking.Get(_mario.Id).Channels.Email);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("m")]
    [InlineData("nome con spazi")]
    [InlineData("mario#1234")]
    [InlineData("abcdefghijklmnopqrstuvwxyz1234567")]
    public async Task DiscordNamesMustLookLikeDiscordNames(string? name) =>
        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, name, "giusta", "it", Ct)).Error);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("mario")]
    [InlineData("mario@localhost")]
    [InlineData("Mario <mario@example.com>")]
    [InlineData("mario@example.com.")]
    [InlineData("mario@[127.0.0.1]")]
    [InlineData("mario@example..com")]
    [InlineData("mario@-example.com")]
    [InlineData("mario@example-.com")]
    [InlineData("mário@example.com")]
    [InlineData("mario@exämple.com")]
    public async Task EmailsMustBeJustAnAddress(string? address) =>
        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, address, "giusta", "it", Ct)).Error);

    [Theory]
    [InlineData("Mario@Example.com")]
    [InlineData("mario.rossi+wf@mail.example.it")]
    public async Task OrdinaryEmailsAreAccepted(string address)
    {
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, address, "giusta", "it", Ct)).Error);

        Assert.Equal(address, Assert.Single(_rig.Mail.Sent).To);
    }

    [Fact]
    public async Task TooLongEmailsAreInvalid()
    {
        var address = new string('a', ContactLinking.MaxEmailLength - "@example.com".Length + 1) + "@example.com";

        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, address, "giusta", "it", Ct)).Error);
    }

    [Fact]
    public async Task UnknownMembersAndSearchErrors()
    {
        Assert.Equal(AccountError.MemberNotFound, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "luigi", "giusta", "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Discord.SearchFails = true;

        Assert.Equal(AccountError.SendFailed, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        Assert.Equal("SendFailed", _rig.Sender.LastError(AccountChannel.Discord)!.Code);
    }

    [Fact]
    public async Task MemberNotFoundLeavesNoCode()
    {
        Assert.Equal(AccountError.MemberNotFound, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "luigi", "giusta", "it", Ct)).Error);

        Assert.Equal(0, _rig.Codes.Count);
        Assert.Empty(_rig.Discord.Sent);
    }

    // Il server di Discord non è sotto il nostro controllo: un membro senza id valido o senza nome non diventa un contatto.
    [Theory]
    [InlineData("abc", "mario")]
    [InlineData("12345", "mario")]
    [InlineData("222222222222222222", "")]
    [InlineData("222222222222222222", "  ")]
    public async Task AMemberThatIsNotValidIsASendFailure(string id, string username)
    {
        _rig.Discord.Members["strano"] = new DiscordMember(id, username);

        Assert.Equal(AccountError.SendFailed, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "strano", "giusta", "it", Ct)).Error);

        Assert.Equal("SendFailed", _rig.Sender.LastError(AccountChannel.Discord)!.Code);
        Assert.Equal(0, _rig.Codes.Count);
        Assert.Empty(_rig.Discord.Sent);
    }

    [Fact]
    public async Task AFailedSendDropsTheCode()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        Assert.Equal(AccountError.DmClosed, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        Assert.Equal(AccountError.SendFailed, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);

        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task OneStartAMinuteFiveAnHour()
    {
        Assert.Null((await Start()).Error);
        Assert.Equal(AccountError.RateLimited, (await Start()).Error);
        for (var i = 0; i < 4; i++)
        {
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
            Assert.Null((await Start()).Error);
        }

        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.RateLimited, (await Start()).Error);

        Task<AccountResult<LinkStartResponse>> Start() =>
            _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct);
    }

    [Fact]
    public async Task ATypoInTheDiscordNameDoesNotUseTheMinute()
    {
        Assert.Equal(AccountError.MemberNotFound, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mari0", "giusta", "it", Ct)).Error);

        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        // Il minuto lo usa il codice mandato.
        Assert.Equal(AccountError.RateLimited, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
    }

    [Fact]
    public async Task DiscordAndEmailHaveTheirOwnMinute()
    {
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);

        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);
        Assert.Equal(AccountError.RateLimited, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);
    }

    [Fact]
    public async Task EveryLookupCountsForTheHour()
    {
        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(AccountError.MemberNotFound, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "luigi", "giusta", "it", Ct)).Error);
        }

        Assert.Equal(AccountError.RateLimited, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        Assert.Equal(5, _rig.Discord.Searches.Count);
    }

    [Fact]
    public async Task AnInvalidTargetUsesNoLimit()
    {
        for (var i = 0; i < 3; i++)
        {
            Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario", "giusta", "it", Ct)).Error);
            Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "m", "giusta", "it", Ct)).Error);
        }

        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
    }

    [Fact]
    public async Task ASecondStartReplacesTheFirstCode()
    {
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "primo@example.com", "giusta", "it", Ct);
        var first = _rig.Mail.LastCode("primo@example.com");
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "secondo@example.com", "giusta", "it", Ct);
        var second = _rig.Mail.LastCode("secondo@example.com");

        // Due codici uguali sono possibili (uno su un milione): allora il primo vale ancora.
        if (first != second)
        {
            Assert.Equal(AccountError.InvalidCode, (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, first)).Error);
        }

        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, second);

        Assert.Null(confirm.Error);
        Assert.Equal("secondo@example.com", confirm.Value!.Email!.Address);
        Assert.Equal("secondo@example.com", _rig.Contacts.Get(_mario.Id).Email!.Address);
    }

    [Fact]
    public async Task ConfirmingRemovesTheReminders()
    {
        await _rig.Inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct);

        await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, _rig.Mail.LastCode("mario@example.com"));

        Assert.Empty(_rig.Inbox.Get(_mario.Id).Entries);
    }

    [Fact]
    public async Task UnlinkRemovesOneChannel()
    {
        var luigi = _rig.UserWithContacts("Luigi");

        Assert.Null(await _linking.UnlinkAsync(luigi.Id, AccountChannel.Discord, "giusta"));

        var contacts = _linking.Get(luigi.Id);
        Assert.Null(contacts.Discord);
        Assert.Equal("luigi@example.com", contacts.Email!.Address);
    }

    [Fact]
    public async Task UnlinkingNeedsTheCurrentPassword()
    {
        var luigi = _rig.UserWithContacts("Luigi");

        Assert.Equal(AccountError.WrongPassword, await _linking.UnlinkAsync(luigi.Id, AccountChannel.Discord, "sbagliata"));
        Assert.Equal(AccountError.WrongPassword, await _linking.UnlinkAsync(luigi.Id, AccountChannel.Email, null));

        var contacts = _linking.Get(luigi.Id);
        Assert.NotNull(contacts.Discord);
        Assert.NotNull(contacts.Email);
    }

    [Fact]
    public async Task WithoutAUserNothingIsUnlinked()
    {
        Assert.Equal(AccountError.Invalid, await _linking.UnlinkAsync(Guid.Empty, AccountChannel.Discord, "giusta"));

        Assert.Empty(_rig.PasswordCheck.Calls);
    }

    [Fact]
    public async Task AWrongPasswordStopsTheStartBeforeAnythingExternal()
    {
        _rig.PasswordCheck.Passwords[_mario.Id] = "quella-vera";

        Assert.Equal(AccountError.WrongPassword, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "sbagliata", "it", Ct)).Error);
        Assert.Equal(AccountError.WrongPassword, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", null, "it", Ct)).Error);

        Assert.Empty(_rig.Discord.Searches);
        Assert.Empty(_rig.Discord.Sent);
        Assert.Empty(_rig.Mail.Sent);
        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task ThePasswordIsAskedOnlyForAStartThatPassesTheOtherChecks()
    {
        _rig.Settings.SmtpHost = string.Empty;
        Assert.Equal(AccountError.ChannelOff, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "sbagliata", "it", Ct)).Error);
        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "m", "sbagliata", "it", Ct)).Error);
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        Assert.Equal(AccountError.RateLimited, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "sbagliata", "it", Ct)).Error);

        Assert.Equal(new[] { (_mario.Id, "giusta") }, _rig.PasswordCheck.Calls);
    }

    [Fact]
    public async Task AnAccountWithoutAPasswordUsesTheEmptyOne()
    {
        _rig.PasswordCheck.Passwords[_mario.Id] = string.Empty;

        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", string.Empty, "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", null, "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.WrongPassword, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "qualcosa", "it", Ct)).Error);

        Assert.Equal(new[] { string.Empty, string.Empty, "qualcosa" }, _rig.PasswordCheck.Calls.Select(c => c.Password));
    }

    [Fact]
    public async Task TenPasswordChecksAnHour()
    {
        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(AccountError.WrongPassword, await _linking.UnlinkAsync(_mario.Id, AccountChannel.Discord, "sbagliata"));
        }

        // La giusta, ma troppo tardi: l'undicesimo controllo non arriva a Jellyfin.
        Assert.Equal(AccountError.RateLimited, await _linking.UnlinkAsync(_mario.Id, AccountChannel.Discord, "giusta"));
        Assert.Equal(10, _rig.PasswordCheck.Calls.Count);
        _rig.Time.Advance(TimeSpan.FromHours(1));
        Assert.Null(await _linking.UnlinkAsync(_mario.Id, AccountChannel.Discord, "giusta"));
    }

    [Fact]
    public async Task AWrongPasswordDoesNotSpendTheHour()
    {
        _rig.PasswordCheck.Passwords[_mario.Id] = "quella-vera";
        for (var i = 0; i < 2; i++)
        {
            Assert.Equal(
                AccountError.WrongPassword,
                (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "sbagliata", "it", Ct)).Error);
        }

        // Cinque codici all'ora restano possibili (uno al minuto).
        for (var i = 0; i < 5; i++)
        {
            Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "quella-vera", "it", Ct)).Error);
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(7, _rig.PasswordCheck.Calls.Count);
        Assert.Equal(
            AccountError.RateLimited,
            (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "quella-vera", "it", Ct)).Error);
    }

    [Fact]
    public async Task TheSixthStartOfTheHourDoesNotReachThePasswordCheck()
    {
        for (var i = 0; i < 5; i++)
        {
            Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }

        var checks = _rig.PasswordCheck.Calls.Count;

        Assert.Equal(
            AccountError.RateLimited,
            (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "sbagliata", "it", Ct)).Error);
        Assert.Equal(checks, _rig.PasswordCheck.Calls.Count);
    }

    [Fact]
    public async Task StartAndUnlinkShareTheTenPasswordChecks()
    {
        _rig.PasswordCheck.Passwords[_mario.Id] = "quella-vera";
        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(
                AccountError.WrongPassword,
                (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "sbagliata", "it", Ct)).Error);
            Assert.Equal(AccountError.WrongPassword, await _linking.UnlinkAsync(_mario.Id, AccountChannel.Email, "sbagliata"));
        }

        // La giusta, ma troppo tardi: né l'avvio né lo scollegamento arrivano a Jellyfin.
        Assert.Equal(
            AccountError.RateLimited,
            (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "quella-vera", "it", Ct)).Error);
        Assert.Equal(AccountError.RateLimited, await _linking.UnlinkAsync(_mario.Id, AccountChannel.Email, "quella-vera"));
        Assert.Equal(10, _rig.PasswordCheck.Calls.Count);

        _rig.Time.Advance(TimeSpan.FromHours(1));
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "quella-vera", "it", Ct)).Error);
    }

    // Scollegare è lo strumento per "questo contatto è compromesso": un codice di recupero già mandato lì non deve più valere.
    [Theory]
    [InlineData(AccountChannel.Discord)]
    [InlineData(AccountChannel.Email)]
    public async Task UnlinkingCancelsAPendingRecoveryCode(AccountChannel channel)
    {
        var luigi = _rig.UserWithContacts("Luigi");
        var recovery = _rig.Recovery();
        var (code, _) = _rig.Codes.Issue(luigi.Id, CodePurpose.Recovery);

        Assert.Null(await _linking.UnlinkAsync(luigi.Id, channel, "giusta"));

        Assert.Equal(0, _rig.Codes.Count);
        Assert.Equal(AccountError.InvalidCode, (await recovery.CompleteAsync("luigi", code, "nuova-password", "it")).Error);
        Assert.Empty(_rig.Passwords.Calls);
    }

    [Fact]
    public async Task UnlinkingCancelsTheCodeEvenIfTheContactWasNotThere()
    {
        _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);

        Assert.Null(await _linking.UnlinkAsync(_mario.Id, AccountChannel.Email, "giusta"));

        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task AWrongPasswordLeavesThePendingRecoveryCode()
    {
        var luigi = _rig.UserWithContacts("Luigi");
        _rig.PasswordCheck.Passwords[luigi.Id] = "quella-vera";
        _rig.Codes.Issue(luigi.Id, CodePurpose.Recovery);

        Assert.Equal(AccountError.WrongPassword, await _linking.UnlinkAsync(luigi.Id, AccountChannel.Discord, "sbagliata"));

        Assert.Equal(1, _rig.Codes.Count);
    }

    [Fact]
    public async Task UnlinkingLeavesTheCodesToVerifyAContact()
    {
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct);

        Assert.Null(await _linking.UnlinkAsync(_mario.Id, AccountChannel.Discord, "giusta"));

        Assert.Equal(1, _rig.Codes.Count);
    }

    [Fact]
    public async Task UnlinkLogsOnlyWhenAContactWasRemoved()
    {
        var luigi = _rig.UserWithContacts("Luigi");
        var logger = new RecordingLogger<ContactLinking>();
        var linking = new ContactLinking(
            _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Discord, _rig.PasswordCheck, _rig.Sender, _rig.Settings, _rig.Inbox, _rig.Time, logger);

        Assert.Null(await linking.UnlinkAsync(luigi.Id, AccountChannel.Discord, "giusta"));
        Assert.Single(logger.Entries, e => e.Message.Contains("scollegato", StringComparison.Ordinal));

        // Il contatto non c'è più: nessun'altra riga "scollegato".
        Assert.Null(await linking.UnlinkAsync(luigi.Id, AccountChannel.Discord, "giusta"));
        Assert.Single(logger.Entries, e => e.Message.Contains("scollegato", StringComparison.Ordinal));
    }

    // Tutte le righe del collegamento scrivono l'id dell'utente senza trattini.
    [Fact]
    public async Task TheLogLinesHaveTheUserIdWithoutDashes()
    {
        var logger = new RecordingLogger<ContactLinking>();
        var linking = new ContactLinking(
            _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Discord, _rig.PasswordCheck, _rig.Sender, _rig.Settings, _rig.Inbox, _rig.Time, logger);

        Assert.Null((await linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "giusta", "it", Ct)).Error);
        Assert.Null((await linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, _rig.Discord.LastCode("222222222222222222"))).Error);
        Assert.Null(await linking.UnlinkAsync(_mario.Id, AccountChannel.Discord, "giusta"));

        Assert.Equal(
            new[]
            {
                $"Codice per collegare Discord mandato all'utente {_mario.Id:N}",
                $"Discord collegato all'utente {_mario.Id:N}",
                $"Discord scollegato dall'utente {_mario.Id:N}",
            },
            logger.Entries.Select(e => e.Message).ToArray());
    }

    [Fact]
    public async Task ConfirmingDoesNotNeedThePassword()
    {
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct);
        _rig.PasswordCheck.Passwords[_mario.Id] = "cambiata";
        var checks = _rig.PasswordCheck.Calls.Count;

        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, _rig.Mail.LastCode("mario@example.com"));

        Assert.Null(confirm.Error);
        Assert.Equal(checks, _rig.PasswordCheck.Calls.Count);
    }

    [Fact]
    public async Task WithoutAUserNothingIsLinked() =>
        Assert.Equal(AccountError.Invalid, (await _linking.StartAsync(Guid.Empty, AccountChannel.Email, "mario@example.com", "giusta", "it", Ct)).Error);
}
