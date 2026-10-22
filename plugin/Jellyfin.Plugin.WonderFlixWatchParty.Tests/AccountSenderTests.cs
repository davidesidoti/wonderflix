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
    public async Task SendToAllReturnsOnlyTheChannelsWhereItArrived()
    {
        var mario = _rig.UserWithContacts("Mario");
        var contacts = _rig.Contacts.Get(mario.Id);
        _rig.Discord.Outcomes[contacts.Discord!.Id] = SendOutcome.DmClosed;

        Assert.Equal(new[] { AccountChannel.Email }, await _rig.Sender.SendToAllAsync(contacts, Message, Ct));

        Assert.Equal("DmClosed", _rig.Sender.LastError(AccountChannel.Discord)!.Code);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Email));
        Assert.Single(_rig.Mail.Sent);

        // Al contrario: Discord arriva, l'email no. L'ordine resta quello dei canali.
        _rig.Discord.Outcomes.Clear();
        _rig.Mail.Outcomes[contacts.Email!.Address] = SendOutcome.Failed;
        Assert.Equal(new[] { AccountChannel.Discord }, await _rig.Sender.SendToAllAsync(contacts, Message, Ct));
        Assert.Equal("SendFailed", _rig.Sender.LastError(AccountChannel.Email)!.Code);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Discord));
    }

    // Non è una prova di tempo: Discord aspetta che l'email sia partita. In sequenza non partirebbe mai.
    [Fact]
    public async Task SendToAllSendsToTheChannelsInParallel()
    {
        var mario = _rig.UserWithContacts("Mario");
        var contacts = _rig.Contacts.Get(mario.Id);
        var mailStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var sender = new AccountSender(new WaitingDiscord(mailStarted.Task), new SignallingMail(mailStarted), _rig.Settings, _rig.Time);

        var sent = await sender.SendToAllAsync(contacts, Message, Ct).WaitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(new[] { AccountChannel.Discord, AccountChannel.Email }, sent);
    }

    // Manda solo dopo che gli viene detto che l'email è partita.
    private sealed class WaitingDiscord(Task mailStarted) : IDiscordSender
    {
        public async Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken)
        {
            await mailStarted.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
            return SendOutcome.Sent;
        }

        public Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken) =>
            Task.FromResult(DiscordLookup.NotFound);

        public Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken) => Task.FromResult(DiscordCheck.Ok);
    }

    private sealed class SignallingMail(TaskCompletionSource started) : IMailSender
    {
        public Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken)
        {
            started.TrySetResult();
            return Task.FromResult(SendOutcome.Sent);
        }
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
