using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _marioSession;

    public InboxServiceTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _marioSession = _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose() => _folder.Dispose();

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private static GroupSummary Group(params string[] participants) =>
        new(Guid.NewGuid(), "Mario · Dune", "Playing", participants);

    [Fact]
    public async Task AnnouncementsReachEveryActiveUser()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);

        var result = await _inbox.AnnounceAsync("  Stasera manutenzione  ");

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(2, result.Value!.Recipients);
        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.Announcement, entry.Type);
        Assert.Equal("Stasera manutenzione", entry.Text);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);
        Assert.Equal(1, _inbox.Get(_luigi.Id).Unread);
        Assert.Empty(_inbox.Get(bowser.Id).Entries);
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task AnnouncementsNeedOneTo500Characters()
    {
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync(null)).Status);
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync("   ")).Status);
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync(new string('a', 501))).Status);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(HubStatus.Ok, (await _inbox.AnnounceAsync(new string('a', 500))).Status);
        // Punti di codice, non unità UTF-16: 500 emoji passano.
        Assert.Equal(HubStatus.Ok, (await _inbox.AnnounceAsync(string.Concat(Enumerable.Repeat("😂", 500)))).Status);
    }

    [Fact]
    public async Task ReadingRemovingAndClearingNotifyOnlyOnChange()
    {
        await _inbox.AnnounceAsync("uno");
        await _inbox.AnnounceAsync("due");
        _server.Sent.Clear();
        var entries = _inbox.Get(_mario.Id).Entries;

        await _inbox.MarkReadAsync(_mario.Id, entries[1].Seq);
        Assert.Equal(1, _inbox.Get(_mario.Id).Unread);
        await _inbox.MarkReadAsync(_mario.Id, entries[1].Seq);
        Assert.Single(_server.SentTo("s-mario"));
        Assert.Empty(_server.SentTo("s-luigi"));

        await _inbox.RemoveAsync(_mario.Id, entries[0].Id);
        await _inbox.RemoveAsync(_mario.Id, entries[0].Id);
        await _inbox.RemoveAsync(_mario.Id, null);
        Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(2, _server.SentTo("s-mario").Count);

        await _inbox.ClearAsync(_mario.Id);
        await _inbox.ClearAsync(_mario.Id);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(3, _server.SentTo("s-mario").Count);
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task EntriesSurviveARestart()
    {
        await _inbox.AnnounceAsync("ciao");

        var again = TestInbox.Create(_server, _folder, _time);

        Assert.Equal("ciao", Assert.Single(again.Get(_mario.Id).Entries).Text);
    }

    [Fact]
    public async Task CleanupDropsOldEntriesAndDeletedUsers()
    {
        await _inbox.AnnounceAsync("vecchio");
        _time.Advance(TimeSpan.FromDays(20));
        await _inbox.AnnounceAsync("recente");
        _time.Advance(TimeSpan.FromDays(11));
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(3, _inbox.Cleanup());

        Assert.Equal(new[] { "recente" }, _inbox.Get(_mario.Id).Entries.Select(e => e.Text));
        Assert.Empty(_inbox.Get(_luigi.Id).Entries);
    }

    [Fact]
    public async Task InvitesNeedAPlayingItemTheInviteeCanSee()
    {
        var group = Group("Mario");
        var peach = _server.AddUser("Peach");

        // Niente in riproduzione: nessuna voce.
        await _inbox.AddInvitesAsync(_marioSession, group, [_luigi.Id]);
        Assert.Empty(_inbox.Get(_luigi.Id).Entries);

        var movie = Guid.NewGuid();
        var poster = Guid.NewGuid();
        _server.Playing["s-mario"] = new PlayingItem(movie, poster);
        // Peach non ha accesso alla libreria del film.
        _server.Unseen.Add((peach.Id, movie));
        await _inbox.AddInvitesAsync(_marioSession, group, [_luigi.Id, peach.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(InboxEntryTypes.Invite, entry.Type);
        Assert.Equal(group.Id.ToString("N"), entry.GroupId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Equal("Dune", entry.Title);
        Assert.Equal(poster.ToString("N"), entry.ImageItemId);
        Assert.False(entry.Read);
        Assert.Empty(_inbox.Get(peach.Id).Entries);
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task ThePlayingItemCanComeFromAnotherParticipant()
    {
        var peach = _server.AddUser("Peach");
        var movie = Guid.NewGuid();
        _server.Playing["s-luigi"] = new PlayingItem(movie, movie);

        await _inbox.AddInvitesAsync(_marioSession, Group("Mario", "Luigi"), [peach.Id]);

        Assert.Single(_inbox.Get(peach.Id).Entries);
    }

    [Fact]
    public async Task ALibraryErrorLeavesNoEntryAndDoesNotThrow()
    {
        _server.Playing["s-mario"] = new PlayingItem(Guid.NewGuid(), Guid.NewGuid());
        _server.LibraryFails = true;

        await _inbox.AddInvitesAsync(_marioSession, Group("Mario"), [_luigi.Id]);

        Assert.Empty(_inbox.Get(_luigi.Id).Entries);
        Assert.Empty(_server.SentTo("s-luigi"));
    }
}
