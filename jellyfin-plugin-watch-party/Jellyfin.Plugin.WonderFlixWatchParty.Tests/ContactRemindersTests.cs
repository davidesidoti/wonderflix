using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactRemindersTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly ContactReminders _reminders;
    private readonly UserRef _mario;

    public ContactRemindersTests()
    {
        _mario = _rig.Server.AddUser("Mario");
        _rig.UserWithContacts("Luigi");
        _rig.Server.AddUser("Peach", isAdmin: true);
        _rig.Server.AddUser("Daisy", enabled: false);
        _reminders = _rig.Reminders();
    }

    public void Dispose() => _rig.Dispose();

    private List<InboxEntry> RemindersOf(UserRef user) =>
        _rig.Inbox.Get(user.Id).Entries.Where(e => e.Type == InboxEntryTypes.ContactReminder).ToList();

    [Fact]
    public async Task OnlyActiveNonAdminUsersWithoutContacts()
    {
        Assert.Equal(1, await _reminders.RunAsync());

        var entry = Assert.Single(RemindersOf(_mario));
        Assert.Equal(new[] { "Discord", "Email" }, entry.Channels);
        Assert.Equal(_rig.Time.GetUtcNow(), _rig.Contacts.Get(_mario.Id).LastReminderAt);
        Assert.All(_rig.Server.Users.Values.Where(u => u.Id != _mario.Id), u => Assert.Empty(RemindersOf(u)));
    }

    [Fact]
    public async Task EveryNDaysAndAlwaysOne()
    {
        await _reminders.RunAsync();
        Assert.Equal(0, await _reminders.RunAsync());
        _rig.Time.Advance(TimeSpan.FromDays(14) - ContactReminders.ReminderTolerance - TimeSpan.FromMinutes(1));
        Assert.Equal(0, await _reminders.RunAsync());

        _rig.Time.Advance(TimeSpan.FromMinutes(1));

        Assert.Equal(1, await _reminders.RunAsync());
        Assert.Equal(_rig.Time.GetUtcNow(), Assert.Single(RemindersOf(_mario)).CreatedAt);
    }

    // Il timer gira ogni 24 ore: qualche millisecondo di ritardo non deve spostare il promemoria di un giorno.
    [Fact]
    public async Task ASmallDelayDoesNotPushTheReminderByADay()
    {
        await _reminders.RunAsync();
        var first = Assert.Single(RemindersOf(_mario)).CreatedAt;

        _rig.Time.Advance(TimeSpan.FromDays(14) - TimeSpan.FromMinutes(30));

        Assert.Equal(1, await _reminders.RunAsync());
        Assert.True(Assert.Single(RemindersOf(_mario)).CreatedAt > first);
    }

    // Un contatto su un canale spento non serve al recupero: è come non averlo.
    [Fact]
    public async Task AContactOnAChannelThatIsOffDoesNotCount()
    {
        var toad = _rig.Server.AddUser("Toad");
        _rig.Contacts.SetEmail(toad.Id, new EmailContact { Address = "toad@example.com", VerifiedAt = _rig.Time.GetUtcNow() });
        _rig.Settings.SmtpHost = string.Empty;

        Assert.Equal(2, await _reminders.RunAsync());

        Assert.Equal(new[] { "Discord" }, Assert.Single(RemindersOf(toad)).Channels);
        Assert.Equal(new[] { "Discord" }, Assert.Single(RemindersOf(_mario)).Channels);
        // Luigi ha il Discord, e Discord è acceso.
        Assert.Empty(RemindersOf(_rig.Server.Users.Values.Single(u => u.Name == "Luigi")));
    }

    [Fact]
    public async Task OffWithZeroDaysOrWithoutChannels()
    {
        _rig.Settings.ContactReminderDays = 0;
        Assert.Equal(0, await _reminders.RunAsync());
        _rig.Settings.ContactReminderDays = 14;
        _rig.Settings.DiscordBotToken = string.Empty;
        _rig.Settings.SmtpHost = string.Empty;

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.Empty(RemindersOf(_mario));
        Assert.Null(_rig.Contacts.Get(_mario.Id).LastReminderAt);
    }

    [Fact]
    public async Task OnlyTheConfiguredChannels()
    {
        _rig.Settings.SmtpHost = string.Empty;

        await _reminders.RunAsync();

        Assert.Equal(new[] { "Discord" }, Assert.Single(RemindersOf(_mario)).Channels);
    }

    [Fact]
    public async Task UsersGoneFromJellyfinLeaveTheContacts()
    {
        var ghost = Guid.NewGuid();
        _rig.Contacts.SetEmail(ghost, new EmailContact { Address = "ghost@example.com", VerifiedAt = _rig.Time.GetUtcNow() });

        await _reminders.RunAsync();

        Assert.DoesNotContain(ghost, _rig.Contacts.All().Keys);
    }

    // Le email degli utenti cancellati non restano nel file neanche con i promemoria spenti o senza canali.
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task UsersGoneFromJellyfinLeaveTheContactsEvenWithTheRemindersOff(bool zeroDays)
    {
        var ghost = Guid.NewGuid();
        _rig.Contacts.SetEmail(ghost, new EmailContact { Address = "ghost@example.com", VerifiedAt = _rig.Time.GetUtcNow() });
        if (zeroDays)
        {
            _rig.Settings.ContactReminderDays = 0;
        }
        else
        {
            _rig.Settings.DiscordBotToken = string.Empty;
            _rig.Settings.SmtpHost = string.Empty;
        }

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.DoesNotContain(ghost, _rig.Contacts.All().Keys);
        Assert.Empty(RemindersOf(_mario));
        Assert.True(_rig.Contacts.Get(_rig.Server.Users.Values.Single(u => u.Name == "Luigi").Id).HasContact);
    }

    [Fact]
    public async Task AnEmptyUserListRemovesNothing()
    {
        var luigi = _rig.Server.Users.Values.Single(u => u.Name == "Luigi");
        _rig.Server.Users.Clear();

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.True(_rig.Contacts.Get(luigi.Id).HasContact);
    }

    [Fact]
    public async Task AnEmptyUserListRemovesNothingEvenWithTheRemindersOff()
    {
        var luigi = _rig.Server.Users.Values.Single(u => u.Name == "Luigi");
        _rig.Server.Users.Clear();
        _rig.Settings.ContactReminderDays = 0;

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.True(_rig.Contacts.Get(luigi.Id).HasContact);
    }
}
