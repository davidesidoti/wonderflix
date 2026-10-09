using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxContactReminderTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;

    public InboxContactReminderTests()
    {
        _mario = _server.AddUser("Mario");
        _server.AddSession("s1", _mario);
        _inbox = TestInbox.Create(_server, _folder, _time);
    }

    public void Dispose() => _folder.Dispose();

    [Fact]
    public async Task ThereIsAlwaysOneReminder()
    {
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);
        _time.Advance(TimeSpan.FromDays(14));
        await _inbox.AddContactReminderAsync(_mario.Id, ["Email"]);

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.ContactReminder, entry.Type);
        Assert.Equal(new[] { "Email" }, entry.Channels);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);
        Assert.False(entry.Read);
        Assert.Equal(2, _server.SentTo("s1").Count);
    }

    [Fact]
    public async Task RemovingTakesOnlyTheReminders()
    {
        await _inbox.AnnounceAsync("ciao");
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord"]);

        await _inbox.RemoveContactRemindersAsync(_mario.Id);

        Assert.Equal(InboxEntryTypes.Announcement, Assert.Single(_inbox.Get(_mario.Id).Entries).Type);
        var notices = _server.SentTo("s1").Count;
        await _inbox.RemoveContactRemindersAsync(_mario.Id);
        Assert.Equal(notices, _server.SentTo("s1").Count);
    }

    [Fact]
    public async Task TheChannelsSurviveTheFile()
    {
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);

        var reloaded = TestInbox.Create(_server, _folder, _time);

        Assert.Equal(new[] { "Discord", "Email" }, Assert.Single(reloaded.Get(_mario.Id).Entries).Channels);
        Assert.Contains("\"Channels\"", File.ReadAllText(_folder.InboxFile));
    }

    [Fact]
    public void RemoveTypeInTheBook()
    {
        var book = new InboxBook();
        var userId = Guid.NewGuid();
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.ContactReminder });
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.Announcement, Text = "ciao" });

        Assert.True(book.RemoveType(userId, InboxEntryTypes.ContactReminder));
        Assert.False(book.RemoveType(userId, InboxEntryTypes.ContactReminder));
        Assert.False(book.RemoveType(Guid.NewGuid(), InboxEntryTypes.ContactReminder));
        Assert.Equal(InboxEntryTypes.Announcement, Assert.Single(book.List(userId)).Type);
    }
}
