using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Gli avvisi agli admin del recupero della password (spec V): avviato e fermato dai limiti.</summary>
public sealed class RecoveryAlertsTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly PasswordRecovery _recovery;
    private readonly UserRef _admin;
    private readonly UserRef _mario;

    public RecoveryAlertsTests()
    {
        _admin = _rig.Server.AddUser("Anna", isAdmin: true);
        _mario = _rig.UserWithContacts("Mario");
        var alerts = new AdminAlerts(_rig.Inbox, _rig.Server, _rig.Time, NullLogger<AdminAlerts>.Instance);
        _recovery = new PasswordRecovery(
            _rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, NullLogger<PasswordRecovery>.Instance, alerts);
    }

    public void Dispose() => _rig.Dispose();

    private IReadOnlyList<InboxEntry> Entries(string type) => _rig.Inbox.Get(_admin.Id).Entries.Where(e => e.Type == type).ToList();

    private async Task<AccountError?> StartAndWait(string typed)
    {
        var start = _recovery.Start(typed, "it");
        await start.Sending;
        return start.Error;
    }

    private async Task<AccountError?> WrongCode(string typed) =>
        (await _recovery.CompleteAsync(typed, "000000", "nuova-password", "it")).Error;

    // Le voci dei codici sbagliati partono in background: si aspetta che ce ne siano count, poi
    // ancora un poco, così una voce in più (che non deve esserci) avrebbe il tempo di arrivare.
    private async Task<IReadOnlyList<InboxEntry>> EventuallyBlocked(int count)
    {
        for (var i = 0; i < 100 && Entries(InboxEntryTypes.RecoveryBlocked).Count < count; i++)
        {
            await Task.Delay(20);
        }

        await Task.Delay(100);
        return Entries(InboxEntryTypes.RecoveryBlocked);
    }

    [Theory]
    [InlineData("Mario")]
    [InlineData("Luigi")]
    public async Task Start_EligibleUser_RaisesRecoveryStarted(string name)
    {
        // Luigi non ha contatti: l'avviso parte lo stesso.
        _rig.Server.AddUser("Luigi");

        Assert.Null(await StartAndWait(" " + name.ToUpperInvariant() + " "));

        var entry = Assert.Single(Entries(InboxEntryTypes.RecoveryStarted));
        Assert.Equal(name, entry.UserName);
        Assert.Equal(name, entry.Title);
        Assert.StartsWith("recovery:", entry.AlertKey, StringComparison.Ordinal);
        Assert.Null(entry.Scope);
    }

    [Theory]
    [InlineData("nessuno")]
    [InlineData("Peach")]
    [InlineData("Daisy")]
    [InlineData("Anna")]
    public async Task Start_UnknownOrDisabledOrAdminName_NoAlert(string name)
    {
        _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.UserWithContacts("Daisy", enabled: false);

        Assert.Null(await StartAndWait(name));

        Assert.Empty(_rig.Inbox.Get(_admin.Id).Entries);
    }

    [Fact]
    public async Task SendForAdmin_NoAlert()
    {
        var sent = await _recovery.SendForAdminAsync(_mario.Id, _admin.Id, "it", CancellationToken.None);

        Assert.Null(sent.Error);
        Assert.Empty(_rig.Inbox.Get(_admin.Id).Entries);
    }

    [Fact]
    public async Task Start_HourOrDayLimitTrips_RaisesBlockedOnce()
    {
        _rig.Server.AddUser("Luigi");

        // Il quinto dell'ora fa scattare il limite dell'ora: una voce sola.
        for (var i = 0; i < 5; i++)
        {
            Assert.Null(await StartAndWait("luigi"));
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(AccountError.RateLimited, await StartAndWait("luigi"));
        var hour = Assert.Single(Entries(InboxEntryTypes.RecoveryBlocked));
        Assert.Equal("Luigi", hour.UserName);
        Assert.Equal("Luigi", hour.Title);
        Assert.Equal(InboxScopes.User, hour.Scope);
        Assert.StartsWith("recovery:", hour.AlertKey, StringComparison.Ordinal);

        // Dopo un'ora il decimo del giorno fa scattare il limite del giorno: una voce nuova.
        _rig.Time.Advance(TimeSpan.FromHours(1));
        for (var i = 0; i < 5; i++)
        {
            Assert.Null(await StartAndWait("luigi"));
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(AccountError.RateLimited, await StartAndWait("luigi"));
        Assert.Equal(2, Entries(InboxEntryTypes.RecoveryBlocked).Count);

        // Un nome che non è un utente non avvisa nessuno.
        for (var i = 0; i < 5; i++)
        {
            Assert.Null(await StartAndWait("nessuno"));
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(AccountError.RateLimited, await StartAndWait("nessuno"));
        Assert.Equal(2, Entries(InboxEntryTypes.RecoveryBlocked).Count);
    }

    [Fact]
    public async Task Start_GlobalLimitTrips_RaisesBlockedEveryone()
    {
        for (var i = 0; i < 30; i++)
        {
            Assert.Null(await StartAndWait("nome" + i));
        }

        Assert.Equal(AccountError.RateLimited, await StartAndWait("altro"));

        var entry = Assert.Single(Entries(InboxEntryTypes.RecoveryBlocked));
        Assert.Equal(InboxScopes.Everyone, entry.Scope);
        Assert.Null(entry.UserName);
        Assert.Equal("WonderFlix", entry.Title);
    }

    [Fact]
    public async Task WrongCodes_FailLimitTrips_RaisesBlocked()
    {
        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(AccountError.InvalidCode, await WrongCode("MARIO"));
            Assert.Equal(AccountError.InvalidCode, await WrongCode("nessuno"));
        }

        Assert.Equal(AccountError.RateLimited, await WrongCode("mario"));

        var entry = Assert.Single(await EventuallyBlocked(1));
        Assert.Equal("Mario", entry.UserName);
        Assert.Equal(InboxScopes.User, entry.Scope);
    }

    [Fact]
    public async Task WrongCodes_GlobalFailLimitTrips_RaisesBlockedEveryone()
    {
        for (var i = 0; i < 100; i++)
        {
            Assert.Equal(AccountError.InvalidCode, await WrongCode("nome" + i));
        }

        Assert.Equal(AccountError.RateLimited, await WrongCode("altro"));

        var entry = Assert.Single(await EventuallyBlocked(1));
        Assert.Equal(InboxScopes.Everyone, entry.Scope);
        Assert.Null(entry.UserName);
    }

    [Fact]
    public async Task Alerts_NeverContainCode()
    {
        Assert.Null(await StartAndWait("mario"));
        var code = _rig.Discord.LastCode(_rig.Contacts.Get(_mario.Id).Discord!.Id);
        for (var i = 0; i < 10; i++)
        {
            await WrongCode("mario");
        }

        Assert.Single(await EventuallyBlocked(1));
        var entries = _rig.Inbox.Get(_admin.Id).Entries;
        Assert.Equal(2, entries.Count);
        var json = JsonSerializer.Serialize(entries);
        Assert.DoesNotContain(code, json, StringComparison.Ordinal);
        Assert.DoesNotContain("000000", json, StringComparison.Ordinal);
        Assert.DoesNotContain("mario@example.com", json, StringComparison.Ordinal);
        Assert.DoesNotContain(_rig.Contacts.Get(_mario.Id).Discord!.Id, json, StringComparison.Ordinal);
    }
}
