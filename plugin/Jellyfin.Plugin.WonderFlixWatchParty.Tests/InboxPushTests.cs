using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Quali voci della cassetta vanno alla push: solo quelle nuove (spec V).</summary>
public sealed class InboxPushTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero));
    private readonly RecordingPush _push = new();
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;

    public InboxPushTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _server.AddSession("s-mario", _mario);
        _inbox = TestInbox.Create(_server, _folder, _time, _push);
    }

    public void Dispose() => _folder.Dispose();

    private sealed class RecordingPush : IInboxPush
    {
        public List<(Guid UserId, InboxEntry Entry)> Delivered { get; } = [];

        public int Calls { get; private set; }

        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh)
        {
            Calls++;
            Delivered.AddRange(fresh);
        }
    }

    private async Task InviteAsync(string inviter)
    {
        var movie = Guid.NewGuid();
        _server.Playing["s-mario"] = new PlayingItem(movie, movie);
        await _inbox.AddInvitesAsync(
            inviter, new GroupSummary(Guid.Parse("11111111-1111-1111-1111-111111111111"), "Mario · Dune", "Playing", ["Mario"]),
            ["s-mario"], [_luigi.Id]);
    }

    [Fact]
    public async Task NewInvite_Pushes()
    {
        await InviteAsync("Mario");

        var (userId, entry) = Assert.Single(_push.Delivered);
        Assert.Equal(_luigi.Id, userId);
        Assert.Equal(InboxEntryTypes.Invite, entry.Type);
    }

    [Fact]
    public async Task SameGroupInviteAgain_DoesNotPush()
    {
        await InviteAsync("Mario");
        await InviteAsync("Mario");

        Assert.Single(_push.Delivered);
        Assert.Equal(1, _push.Calls);
    }

    [Fact]
    public async Task RecommendationUpdate_DoesNotPush()
    {
        var item = new RecommendableItem(Guid.NewGuid(), "Dune", 2021);

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", item, "bello", [_luigi.Id]);
        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", item, "davvero bello", [_luigi.Id]);

        var (_, entry) = Assert.Single(_push.Delivered);
        Assert.Equal(InboxEntryTypes.Recommendation, entry.Type);
    }

    [Fact]
    public async Task ContactReminderRewritten_PushesOnlyFirstTime()
    {
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord"]);
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);

        Assert.Single(_push.Delivered);
        Assert.Equal(new[] { "Discord", "Email" }, Assert.Single(_inbox.Get(_mario.Id).Entries).Channels);

        // Tolto il promemoria, uno nuovo è di nuovo una novità.
        await _inbox.RemoveContactRemindersAsync(_mario.Id);
        await _inbox.AddContactReminderAsync(_mario.Id, ["Email"]);
        Assert.Equal(2, _push.Delivered.Count);
    }

    [Fact]
    public async Task RequestPendingSameRequestAgain_DoesNotPush()
    {
        var request = new RequestEvent(7, "movie", 42, "Dune", null, null);

        await _inbox.AddRequestPendingAsync([_mario.Id], request, "Luigi");
        await _inbox.AddRequestPendingAsync([_mario.Id], request, "Luigi");
        Assert.Single(_push.Delivered);

        await _inbox.AddRequestPendingAsync([_mario.Id], request with { RequestId = 8 }, "Luigi");
        Assert.Equal(2, _push.Delivered.Count);
    }

    [Fact]
    public async Task MarkReadRemoveClear_DoNotPush()
    {
        await _inbox.AnnounceAsync("ciao");
        var calls = _push.Calls;
        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);

        await _inbox.MarkReadAsync(_mario.Id, entry.Seq);
        await _inbox.RemoveAsync(_mario.Id, entry.Id);
        await _inbox.ClearAsync(_luigi.Id);
        _time.Advance(InboxService.MaxAge + TimeSpan.FromDays(1));
        _inbox.Cleanup();

        Assert.Equal(calls, _push.Calls);
        Assert.Equal(2, _push.Delivered.Count);
    }

    [Fact]
    public void FreshAreTakenOnce()
    {
        var book = new InboxBook();
        var userId = Guid.NewGuid();
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.Announcement });
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.ContactReminder }, fresh: false);

        Assert.Equal(InboxEntryTypes.Announcement, Assert.Single(book.TakeFresh()).Item2.Type);
        Assert.Empty(book.TakeFresh());
    }

    [Fact]
    public async Task ThrowingPush_DoesNotBreakTheInbox()
    {
        var inbox = TestInbox.Create(_server, _folder, _time, new ThrowingPush());

        var result = await inbox.AnnounceAsync("ciao");

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Single(inbox.Get(_mario.Id).Entries);
    }

    private sealed class ThrowingPush : IInboxPush
    {
        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh) => throw new InvalidOperationException("push rotta");
    }
}
