using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountAdminTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
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

        Assert.Equal(AccountError.UnknownUser, _admin.Unlink(Guid.NewGuid()));
        Assert.Null(_admin.Unlink(mario.Id));
        Assert.False(_rig.Contacts.Get(mario.Id).HasContact);
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
        Assert.Equal("MemberNotFound", (await _admin.TestAsync(Guid.Empty, "it", "nome con spazi", null, Ct)).Discord);
        _rig.Discord.SearchFails = true;
        Assert.Equal("SendFailed", (await _admin.TestAsync(Guid.Empty, "it", "davide", null, Ct)).Discord);
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
}
