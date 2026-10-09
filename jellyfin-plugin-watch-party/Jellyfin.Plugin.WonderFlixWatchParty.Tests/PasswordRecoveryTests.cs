using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PasswordRecoveryTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;

    // Chi chiama le funzioni dell'admin (un admin qualsiasi: conta solo che finisca nel log).
    private static readonly Guid AdminId = Guid.NewGuid();
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

    // Chiede un codice e aspetta che l'invio in background finisca; restituisce l'errore, se c'è.
    private async Task<AccountError?> StartAndWait(string typed)
    {
        var start = _recovery.Start(typed, "it");
        await start.Sending;
        return start.Error;
    }

    // Il registro e il recupero con un logger che ricorda le righe, per leggere cosa finisce nel log.
    private (PasswordRecovery Recovery, RecordingLogger<PasswordRecovery> Logger) Logged()
    {
        var logger = new RecordingLogger<PasswordRecovery>();
        return (new PasswordRecovery(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, logger), logger);
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
        Assert.Null(await StartAndWait("luigi"));
        for (var i = 0; i < 4; i++)
        {
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
            Assert.Null(await StartAndWait("mario"));
        }

        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.RateLimited, _recovery.Start("mario", "it").Error);
    }

    [Fact]
    public async Task ThirtyStartsAnHourForEveryone()
    {
        for (var i = 0; i < 30; i++)
        {
            Assert.Null(await StartAndWait("nome" + i));
        }

        Assert.Equal(AccountError.RateLimited, _recovery.Start("altro", "it").Error);
    }

    [Fact]
    public async Task TenStartsADayForEachName()
    {
        // Un'ora fra una richiesta e l'altra: minuto e ora non scattano mai, solo il giorno.
        for (var i = 0; i < 10; i++)
        {
            Assert.Null(await StartAndWait("mario"));
            _rig.Time.Advance(TimeSpan.FromHours(1));
        }

        for (var i = 0; i < 3; i++)
        {
            Assert.Equal(AccountError.RateLimited, _recovery.Start("MARIO", "it").Error);
        }

        // Le richieste rifiutate non contano: 24 ore dopo la prima, il nome torna libero. Gli altri nomi non c'entrano.
        Assert.Null(await StartAndWait("luigi"));
        _rig.Time.Advance(TimeSpan.FromHours(14));
        Assert.Null(await StartAndWait("mario"));
    }

    [Fact]
    public async Task ARequestRefusedByTheNameLimitsDoesNotSpendTheBudgetOfEveryone()
    {
        // Il minuto di "mario" è già preso: le sue richieste sono rifiutate e non devono consumare le trenta di tutti.
        Assert.True(_rig.Limiter.TryAcquire("mario", LimitTypes.RecoveryStartMinute));
        for (var i = 0; i < 40; i++)
        {
            Assert.Equal(AccountError.RateLimited, _recovery.Start("mario", "it").Error);
        }

        for (var i = 0; i < 30; i++)
        {
            Assert.Null(await StartAndWait("nome" + i));
        }

        Assert.Equal(AccountError.RateLimited, _recovery.Start("altro", "it").Error);
    }

    [Fact]
    public async Task ARequestRefusedByTheGlobalLimitDoesNotSpendTheBudgetOfTheName()
    {
        for (var i = 0; i < 30; i++)
        {
            Assert.Null(await StartAndWait("nome" + i));
        }

        // Trenta richieste di tutti già fatte: quelle di "mario" sono rifiutate e il suo minuto, ora e giorno restano interi.
        for (var i = 0; i < 20; i++)
        {
            Assert.Equal(AccountError.RateLimited, _recovery.Start("mario", "it").Error);
        }

        Assert.False(_rig.Limiter.IsLimited("mario", LimitTypes.RecoveryStartMinute));
        Assert.False(_rig.Limiter.IsLimited("mario", LimitTypes.RecoveryStartHour));
        _rig.Time.Advance(TimeSpan.FromHours(1));
        for (var i = 0; i < 5; i++)
        {
            Assert.Null(await StartAndWait("mario"));
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }
    }

    [Fact]
    public async Task ConcurrentStartsCannotOvershootTheNameLimit()
    {
        var recovery = new PasswordRecovery(
            _rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, NullLogger<PasswordRecovery>.Instance);

        var results = await Task.WhenAll(Enumerable.Range(0, 20).Select(_ => Task.Run(() => recovery.Start("mario", "it"))));
        await Task.WhenAll(results.Select(r => r.Sending));

        Assert.Equal(1, results.Count(r => r.Error is null));
        Assert.Equal(19, results.Count(r => r.Error == AccountError.RateLimited));
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
        var (recovery, logger) = Logged();

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
        var (recovery, logger) = Logged();

        for (var i = 0; i < 10; i++)
        {
            await recovery.CompleteAsync("segreto@example.com", "000000", "nuova-password", "it");
        }

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.DoesNotContain("segreto", warning.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("Recupero della password fermato dai limiti per un nome che non è un utente", warning.Message);
    }

    // Il registro è solo del server: dice di chi è il nome anche per un admin o un utente disattivato,
    // anche se il recupero per loro non vale.
    [Theory]
    [InlineData("Peach", true, true)]
    [InlineData("Daisy", false, false)]
    public async Task TheLogHasTheIdOfAnAdminOrADisabledUserToo(string name, bool isAdmin, bool enabled)
    {
        var user = _rig.UserWithContacts(name, isAdmin, enabled);
        var (recovery, logger) = Logged();

        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(AccountError.InvalidCode, (await recovery.CompleteAsync(name.ToUpperInvariant(), "000000", "nuova-password", "it")).Error);
        }

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Equal($"Recupero della password fermato dai limiti per {user.Id:N}", warning.Message);
    }

    [Fact]
    public async Task TheLogShowsWhenTheDailyLimitStopsEveryoneOnlyOnce()
    {
        var (recovery, logger) = Logged();

        // Cento nomi diversi: nessun nome arriva al suo limite, il cento-esimo errore ferma tutti. Gli altri non arrivano al log.
        for (var i = 0; i < 105; i++)
        {
            await recovery.CompleteAsync("nome" + i, "000000", "nuova-password", "it");
        }

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Equal("Recupero della password fermato per tutti: troppi codici sbagliati oggi", warning.Message);
    }

    [Fact]
    public async Task WithoutAnySendTheLogHasAWarning()
    {
        var (recovery, logger) = Logged();
        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        await recovery.Start("mario", "it").Sending;

        var warning = Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Contains("nessun canale", warning.Message, StringComparison.Ordinal);
        Assert.StartsWith($"Codice di recupero di {_mario.Id:N} non mandato", warning.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AJellyfinErrorIsInTheLogWithTheUserIdWithoutDashes()
    {
        var (recovery, logger) = Logged();
        var start = recovery.Start("mario", "it");
        await start.Sending;
        var code = _rig.Discord.LastCode(DiscordId(_mario));
        _rig.Passwords.Error = new InvalidOperationException("database");

        await Assert.ThrowsAsync<InvalidOperationException>(() => recovery.CompleteAsync("mario", code, "nuova-password", "it"));

        var entry = Assert.Single(logger.Entries, e => e.Level == LogLevel.Error);
        Assert.Equal($"Password di {_mario.Id:N} non cambiata", entry.Message);
    }

    [Fact]
    public async Task ConcurrentFailuresCannotOvershootTheLimits()
    {
        // Un elenco utenti lento allarga il tempo fra il controllo dei limiti e il loro conteggio:
        // senza un lucchetto passerebbero in molti prima che il decimo errore sia contato.
        var recovery = new PasswordRecovery(
            new SlowUsers(_rig.Server), _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, NullLogger<PasswordRecovery>.Instance);

        var errors = await Task.WhenAll(Enumerable.Range(0, 30).Select(_ =>
            Task.Run(async () => (await recovery.CompleteAsync("mario", "000000", "nuova-password", "it")).Error)));

        Assert.Equal(10, errors.Count(e => e == AccountError.InvalidCode));
        Assert.Equal(20, errors.Count(e => e == AccountError.RateLimited));
    }

    [Fact]
    public async Task TheAdminCodeIsInTheLogWithTheAdmin()
    {
        var (recovery, logger) = Logged();

        Assert.Null((await recovery.SendForAdminAsync(_mario.Id, AdminId, "it", Ct)).Error);

        var entry = Assert.Single(logger.Entries, e => e.Level == LogLevel.Information);
        Assert.Equal($"Codice di recupero di {_mario.Id:N} mandato dall'admin {AdminId:N} su 2 canali", entry.Message);
    }

    // Con una chiave API non c'è un utente (id tutto a zero): nel registro si legge "chiave API", non zeri.
    [Fact]
    public async Task TheAdminCodeWithAnApiKeyIsInTheLogAsSuch()
    {
        var (recovery, logger) = Logged();

        Assert.Null((await recovery.SendForAdminAsync(_mario.Id, Guid.Empty, "it", Ct)).Error);

        var entry = Assert.Single(logger.Entries, e => e.Level == LogLevel.Information);
        Assert.Equal($"Codice di recupero di {_mario.Id:N} mandato dall'admin chiave API su 2 canali", entry.Message);
        Assert.DoesNotContain("00000000", entry.Message, StringComparison.Ordinal);
    }

    // Tutte le righe del recupero scrivono l'id dell'utente senza trattini.
    [Fact]
    public async Task TheLogLinesHaveTheUserIdWithoutDashes()
    {
        var (recovery, logger) = Logged();
        var start = recovery.Start("mario", "it");
        await start.Sending;
        var code = _rig.Discord.LastCode(DiscordId(_mario));

        var complete = await recovery.CompleteAsync("mario", code, "nuova-password", "it");
        await complete.Notifying;

        Assert.Contains(logger.Entries, e => e.Message == $"Codice di recupero di {_mario.Id:N} mandato su 2 canali");
        Assert.Contains(logger.Entries, e => e.Message == $"Password di {_mario.Id:N} cambiata con il codice di recupero");
        Assert.DoesNotContain(logger.Entries, e => e.Message.Contains(_mario.Id.ToString(), StringComparison.Ordinal));
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

        Assert.Equal(AccountError.UnknownUser, (await _recovery.SendForAdminAsync(Guid.NewGuid(), AdminId, "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(peach.Id, AdminId, "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(daisy.Id, AdminId, "it", Ct)).Error);
        Assert.Equal(AccountError.NoContacts, (await _recovery.SendForAdminAsync(luigi.Id, AdminId, "it", Ct)).Error);
        Assert.Equal(new[] { "Discord", "Email" }, (await _recovery.SendForAdminAsync(_mario.Id, AdminId, "it", Ct)).Value!.Channels);

        // Nessun limite per l'admin: subito di nuovo.
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        Assert.Equal(new[] { "Discord" }, (await _recovery.SendForAdminAsync(_mario.Id, AdminId, "it", Ct)).Value!.Channels);
        var complete = await _recovery.CompleteAsync("mario", _rig.Discord.LastCode(DiscordId(_mario)), "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;

        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.Failed;
        Assert.Equal(AccountError.SendFailed, (await _recovery.SendForAdminAsync(_mario.Id, AdminId, "it", Ct)).Error);
        Assert.Equal(0, _rig.Codes.Count);
    }

    // Un elenco utenti che ci mette un po': rende lunga la parte fra il controllo dei limiti e il loro conteggio.
    private sealed class SlowUsers(IUserDirectory inner) : IUserDirectory
    {
        public IReadOnlyList<UserRef> GetUsers()
        {
            Thread.Sleep(5);
            return inner.GetUsers();
        }

        public UserRef? GetUser(Guid userId) => inner.GetUser(userId);
    }
}
