using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactReminderHostedServiceTests : IDisposable
{
    private readonly AccountRig _rig = new();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task FirstAfterFiveMinutesThenEveryDay()
    {
        var mario = _rig.Server.AddUser("Mario");
        _rig.Settings.ContactReminderDays = 1;
        using var service = new ContactReminderHostedService(
            _rig.Reminders(), _rig.Contacts, _rig.Time, NullLogger<ContactReminderHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);

        _rig.Time.Advance(ContactReminderHostedService.FirstRun - TimeSpan.FromSeconds(1));
        Assert.Empty(_rig.Inbox.Get(mario.Id).Entries);
        _rig.Time.Advance(TimeSpan.FromSeconds(1));
        var first = Assert.Single(_rig.Inbox.Get(mario.Id).Entries);
        _rig.Time.Advance(ContactReminderHostedService.Interval);
        var second = Assert.Single(_rig.Inbox.Get(mario.Id).Entries);
        Assert.True(second.Seq > first.Seq);

        await service.StopAsync(CancellationToken.None);
        _rig.Time.Advance(ContactReminderHostedService.Interval);

        Assert.Equal(second.Seq, Assert.Single(_rig.Inbox.Get(mario.Id).Entries).Seq);
    }

    [Fact]
    public async Task AFailureEndsInTheLog()
    {
        _rig.Settings.ContactReminderDays = 1;
        var logger = new RecordingLogger<ContactReminderHostedService>();
        var failing = new ContactReminders(
            new ThrowingUsers(), _rig.Contacts, _rig.Inbox, _rig.Settings, _rig.Time, NullLogger<ContactReminders>.Instance);
        using var service = new ContactReminderHostedService(failing, _rig.Contacts, _rig.Time, logger);
        await service.StartAsync(CancellationToken.None);

        _rig.Time.Advance(ContactReminderHostedService.FirstRun);

        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
        await service.StopAsync(CancellationToken.None);
    }

    private sealed class ThrowingUsers : IUserDirectory
    {
        public IReadOnlyList<UserRef> GetUsers() => throw new InvalidOperationException("database");

        public UserRef? GetUser(Guid userId) => throw new InvalidOperationException("database");
    }
}
