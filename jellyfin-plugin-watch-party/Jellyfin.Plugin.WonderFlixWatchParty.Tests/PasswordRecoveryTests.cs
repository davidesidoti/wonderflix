using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PasswordRecoveryTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly AccountRig _rig = new();
    private readonly PasswordRecovery _recovery;
    private readonly UserRef _mario;

    public PasswordRecoveryTests()
    {
        _mario = _rig.UserWithContacts("Mario");
        _recovery = _rig.Recovery();
    }

    public void Dispose() => _rig.Dispose();

    private string DiscordId(UserRef user) => _rig.Contacts.Get(user.Id).Discord!.Id;

    // Chiede il codice scrivendo il nome così, aspetta l'invio e lo legge dal DM.
    private async Task<string> CodeFor(UserRef user, string typed)
    {
        var start = _recovery.Start(typed, "it");
        Assert.Null(start.Error);
        await start.Sending;
        return _rig.Discord.LastCode(DiscordId(user));
    }

    [Fact]
    public async Task TheCodeGoesToEveryContact()
    {
        var code = await CodeFor(_mario, " MARIO ");

        Assert.Contains("«Mario»", _rig.Discord.Sent.Single().Text);
        Assert.Equal(code, _rig.Mail.LastCode("mario@example.com"));
    }

    [Theory]
    [InlineData("nessuno")]
    [InlineData("Peach")]
    [InlineData("Daisy")]
    [InlineData("Luigi")]
    public async Task StartLooksTheSameForEveryone(string name)
    {
        _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.UserWithContacts("Daisy", enabled: false);
        _rig.Server.AddUser("Luigi");

        var start = _recovery.Start(name, "it");

        Assert.Null(start.Error);
        await start.Sending;
        Assert.Empty(_rig.Discord.Sent);
        Assert.Empty(_rig.Mail.Sent);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ANameIsNeeded(string? name) =>
        Assert.Equal(AccountError.Invalid, _recovery.Start(name, "it").Error);

    [Fact]
    public void TooLongNamesAreInvalid() =>
        Assert.Equal(AccountError.Invalid, _recovery.Start(new string('a', PasswordRecovery.MaxUsernameLength + 1), "it").Error);

    [Fact]
    public async Task OneStartAMinuteAndFiveAnHourForEachName()
    {
        await CodeFor(_mario, "mario");
        Assert.Equal(AccountError.RateLimited, _recovery.Start("MARIO", "it").Error);
        Assert.Null(_recovery.Start("luigi", "it").Error);
        for (var i = 0; i < 4; i++)
        {
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
            Assert.Null(_recovery.Start("mario", "it").Error);
        }

        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.RateLimited, _recovery.Start("mario", "it").Error);
    }

    [Fact]
    public void ThirtyStartsAnHourForEveryone()
    {
        for (var i = 0; i < 30; i++)
        {
            Assert.Null(_recovery.Start("nome" + i, "it").Error);
        }

        Assert.Equal(AccountError.RateLimited, _recovery.Start("altro", "it").Error);
    }

    [Fact]
    public async Task TheCodeChangesThePasswordAndTheUserIsWarned()
    {
        var code = await CodeFor(_mario, "mario");

        var complete = await _recovery.CompleteAsync("Mario", code, "nuova-password", "it");

        Assert.Null(complete.Error);
        await complete.Notifying;
        Assert.Equal(new[] { (_mario.Id, "nuova-password") }, _rig.Passwords.Calls);
        Assert.Contains("è stata cambiata", _rig.Discord.Sent.Last().Text);
        Assert.Equal("WonderFlix — password cambiata", _rig.Mail.Sent.Last().Message.Subject);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", code, "altra-password", "it")).Error);
    }

    [Fact]
    public async Task AWrongLengthPasswordDoesNotUseAnAttempt()
    {
        var code = await CodeFor(_mario, "mario");
        for (var i = 0; i < CodeBook.MaxAttempts; i++)
        {
            Assert.Equal(AccountError.WeakPassword, (await _recovery.CompleteAsync("mario", code, "12345", "it")).Error);
        }

        Assert.Equal(
            AccountError.WeakPassword,
            (await _recovery.CompleteAsync("mario", code, new string('x', PasswordRecovery.MaxPasswordLength + 1), "it")).Error);
        var complete = await _recovery.CompleteAsync("mario", code, "123456", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task OnlyEligibleUsersCanUseACode()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        var (code, _) = _rig.Codes.Issue(peach.Id, CodePurpose.Recovery);

        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("peach", code, "nuova-password", "it")).Error);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("nessuno", "123456", "nuova-password", "it")).Error);
        Assert.Empty(_rig.Passwords.Calls);
    }

    [Fact]
    public async Task TenFailuresStopTheNameForAnHour()
    {
        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", "000000", "nuova-password", "it")).Error);
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("MARIO", code, "nuova-password", "it")).Error);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("luigi", "000000", "nuova-password", "it")).Error);

        _rig.Time.Advance(TimeSpan.FromHours(1));
        (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        var complete = await _recovery.CompleteAsync("mario", code, "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task TwentyFailuresStopTheNameForADay()
    {
        for (var hour = 0; hour < 2; hour++)
        {
            for (var i = 0; i < 10; i++)
            {
                Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", "000000", "nuova-password", "it")).Error);
            }

            _rig.Time.Advance(TimeSpan.FromHours(1));
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("mario", code, "nuova-password", "it")).Error);

        // Un giorno dopo il primo errore il nome torna libero.
        _rig.Time.Advance(TimeSpan.FromHours(22));
        (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        var complete = await _recovery.CompleteAsync("mario", code, "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task AHundredFailuresStopEveryone()
    {
        for (var i = 0; i < 100; i++)
        {
            Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("nome" + i, "000000", "nuova-password", "it")).Error);
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("mario", code, "nuova-password", "it")).Error);
    }

    [Fact]
    public async Task WithoutAnySendTheCodeIsDropped()
    {
        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        var start = _recovery.Start("mario", "it");
        await start.Sending;

        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task TheLogShowsWhenTheLimitStopsANameOnlyOnce()
    {
        var logger = new RecordingLogger<PasswordRecovery>();
        var recovery = new PasswordRecovery(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, logger);

        // Nove errori non bastano; il decimo ferma il nome e lo scrive nel log, l'undicesimo non arriva fin lì.
        for (var i = 0; i < 11; i++)
        {
            await recovery.CompleteAsync("mario", "000000", "nuova-password", "it");
        }

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Equal($"Recupero della password fermato dai limiti per {_mario.Id:N}", warning.Message);
    }

    [Fact]
    public async Task TheLogNeverHasTheTypedTextForAnUnknownName()
    {
        var logger = new RecordingLogger<PasswordRecovery>();
        var recovery = new PasswordRecovery(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, logger);

        for (var i = 0; i < 10; i++)
        {
            await recovery.CompleteAsync("segreto@example.com", "000000", "nuova-password", "it");
        }

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.DoesNotContain("segreto", warning.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task WithoutAnySendTheLogHasAWarning()
    {
        var logger = new RecordingLogger<PasswordRecovery>();
        var recovery = new PasswordRecovery(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, logger);
        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        await recovery.Start("mario", "it").Sending;

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Contains("nessun canale", warning.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AJellyfinErrorComesOut()
    {
        var code = await CodeFor(_mario, "mario");
        _rig.Passwords.Error = new InvalidOperationException("database");

        await Assert.ThrowsAsync<InvalidOperationException>(() => _recovery.CompleteAsync("mario", code, "nuova-password", "it"));
    }

    [Fact]
    public async Task TheAdminSendsTheCodeAndGetsTheTruth()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        var daisy = _rig.UserWithContacts("Daisy", enabled: false);
        var luigi = _rig.Server.AddUser("Luigi");

        Assert.Equal(AccountError.UnknownUser, (await _recovery.SendForAdminAsync(Guid.NewGuid(), "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(peach.Id, "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(daisy.Id, "it", Ct)).Error);
        Assert.Equal(AccountError.NoContacts, (await _recovery.SendForAdminAsync(luigi.Id, "it", Ct)).Error);
        Assert.Equal(new[] { "Discord", "Email" }, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Value!.Channels);

        // Nessun limite per l'admin: subito di nuovo.
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        Assert.Equal(new[] { "Discord" }, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Value!.Channels);
        var complete = await _recovery.CompleteAsync("mario", _rig.Discord.LastCode(DiscordId(_mario)), "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;

        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.Failed;
        Assert.Equal(AccountError.SendFailed, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Error);
        Assert.Equal(0, _rig.Codes.Count);
    }
}
