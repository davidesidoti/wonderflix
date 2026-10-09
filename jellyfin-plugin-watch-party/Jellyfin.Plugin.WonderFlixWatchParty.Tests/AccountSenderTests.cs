using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountSenderTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private static readonly AccountMessage Message = new("Oggetto", "Testo 123456");
    private readonly AccountRig _rig = new();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task EachChannelGoesToItsSender()
    {
        Assert.Equal(SendOutcome.Sent, await _rig.Sender.SendAsync(AccountChannel.Discord, "222222222222222222", Message, Ct));
        Assert.Equal(SendOutcome.Sent, await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct));

        Assert.Equal(new[] { ("222222222222222222", "Testo 123456") }, _rig.Discord.Sent);
        var mail = Assert.Single(_rig.Mail.Sent);
        Assert.Equal("mario@example.com", mail.To);
        Assert.Equal(Message, mail.Message);
    }

    [Fact]
    public async Task AChannelThatIsOffSendsAndRecordsNothing()
    {
        _rig.Settings.SmtpHost = string.Empty;

        Assert.Equal(SendOutcome.Failed, await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct));

        Assert.Empty(_rig.Mail.Sent);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Email));
    }

    [Fact]
    public async Task SendToAllUsesTheConfiguredChannelsWithAContact()
    {
        var mario = _rig.UserWithContacts("Mario");
        var contacts = _rig.Contacts.Get(mario.Id);

        Assert.Equal(
            new[] { AccountChannel.Discord, AccountChannel.Email },
            await _rig.Sender.SendToAllAsync(contacts, Message, Ct));
        _rig.Settings.DiscordBotToken = string.Empty;
        Assert.Equal(new[] { AccountChannel.Email }, await _rig.Sender.SendToAllAsync(contacts, Message, Ct));
        Assert.Equal(new[] { (AccountChannel.Email, "mario@example.com") }, _rig.Sender.Targets(contacts));
        Assert.Empty(await _rig.Sender.SendToAllAsync(new UserContacts(), Message, Ct));
    }

    [Fact]
    public async Task TheLastErrorStaysUntilASend()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        await _rig.Sender.SendAsync(AccountChannel.Discord, "222222222222222222", Message, Ct);
        Assert.Equal(new SendError(_rig.Time.GetUtcNow(), "DmClosed"), _rig.Sender.LastError(AccountChannel.Discord));
        Assert.Null(_rig.Sender.LastError(AccountChannel.Email));

        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct);
        Assert.Equal(new SendError(_rig.Time.GetUtcNow(), "SendFailed"), _rig.Sender.LastError(AccountChannel.Email));

        _rig.Sender.RecordInvalid(AccountChannel.Discord);
        Assert.Equal("Invalid", _rig.Sender.LastError(AccountChannel.Discord)!.Code);

        await _rig.Sender.SendAsync(AccountChannel.Discord, "333333333333333333", Message, Ct);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Discord));
    }
}
