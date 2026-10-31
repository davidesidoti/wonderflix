using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Le voci degli admin per chiave (spec V): si aprono, si aggiornano e si chiudono.</summary>
public sealed class AdminAlertsTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero));
    private readonly RecordingPush _push = new();
    private readonly InboxService _inbox;
    private readonly AdminAlerts _alerts;
    private readonly UserRef _anna;
    private readonly UserRef _bruno;

    public AdminAlertsTests()
    {
        _anna = _server.AddUser("Anna", isAdmin: true);
        _bruno = _server.AddUser("Bruno", isAdmin: true);
        _inbox = TestInbox.Create(_server, _folder, _time, _push);
        _alerts = new AdminAlerts(_inbox, _server, _time, NullLogger<AdminAlerts>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private sealed class RecordingPush : IInboxPush
    {
        public List<(Guid UserId, InboxEntry Entry)> Delivered { get; } = [];

        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh) => Delivered.AddRange(fresh);
    }

    private static AdminAlert NeedsYou(string key, string reason = "NothingFound") =>
        new(key, InboxEntryTypes.DownloadNeedsYou, "Dune", Reason: reason);

    [Fact]
    public async Task Sync_NewKey_AddsAndPushes()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);

        foreach (var admin in new[] { _anna, _bruno })
        {
            var entry = Assert.Single(_inbox.Get(admin.Id).Entries);
            Assert.Equal("download:1", entry.AlertKey);
            Assert.Equal(InboxEntryTypes.DownloadNeedsYou, entry.Type);
            Assert.Equal("NothingFound", entry.Reason);
            Assert.Equal("Dune", entry.Title);
            Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);
            Assert.False(entry.Read);
        }

        Assert.Equal(new[] { _anna.Id, _bruno.Id }.Order(), _push.Delivered.Select(d => d.UserId).Order());
    }

    [Fact]
    public async Task Sync_SameKeyTypeReason_NoPush()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);
        var before = Assert.Single(_inbox.Get(_anna.Id).Entries);

        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);

        var after = Assert.Single(_inbox.Get(_anna.Id).Entries);
        Assert.Equal(before.Id, after.Id);
        Assert.Equal(before.Seq, after.Seq);
        Assert.Equal(2, _push.Delivered.Count);
    }

    [Fact]
    public async Task Sync_SameKeyNewReason_Replaces()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);
        var before = Assert.Single(_inbox.Get(_anna.Id).Entries);
        await _inbox.MarkReadAsync(_anna.Id, before.Seq);

        await _alerts.SyncAsync("download:", [NeedsYou("download:1", "GrabRefused")]);

        var after = Assert.Single(_inbox.Get(_anna.Id).Entries);
        Assert.NotEqual(before.Id, after.Id);
        Assert.True(after.Seq > before.Seq);
        Assert.Equal("GrabRefused", after.Reason);
        Assert.False(after.Read);
        Assert.Equal(4, _push.Delivered.Count);
    }

    [Fact]
    public async Task Sync_MissingKey_RemovedFromAllAdmins()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1"), NeedsYou("download:2")]);

        await _alerts.SyncAsync("download:", [NeedsYou("download:2")]);

        Assert.Equal("download:2", Assert.Single(_inbox.Get(_anna.Id).Entries).AlertKey);
        Assert.Equal("download:2", Assert.Single(_inbox.Get(_bruno.Id).Entries).AlertKey);

        await _alerts.SyncAsync("download:", []);

        Assert.Empty(_inbox.Get(_anna.Id).Entries);
        Assert.Empty(_inbox.Get(_bruno.Id).Entries);
    }

    [Fact]
    public async Task Sync_OtherPrefixUntouched()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);
        await _alerts.SyncAsync("quota", [new("quota", InboxEntryTypes.DiskAlmostFull, "Disco", Percent: 91)]);
        await _inbox.AnnounceAsync("ciao");

        await _alerts.SyncAsync("download:", []);

        var entries = _inbox.Get(_anna.Id).Entries;
        Assert.Equal(2, entries.Count);
        Assert.Contains(entries, e => e.AlertKey == "quota");
        Assert.Contains(entries, e => e.Type == InboxEntryTypes.Announcement);
    }

    [Fact]
    public async Task Sync_PercentChange_UpdatesWithoutPush()
    {
        await _alerts.SyncAsync("quota", [new("quota", InboxEntryTypes.DiskAlmostFull, "Disco", Percent: 91)]);
        var before = Assert.Single(_inbox.Get(_anna.Id).Entries);
        await _inbox.MarkReadAsync(_anna.Id, before.Seq);
        _server.AddSession("s-anna", _anna);

        await _alerts.SyncAsync("quota", [new("quota", InboxEntryTypes.DiskAlmostFull, "Disco", Percent: 95)]);

        var after = Assert.Single(_inbox.Get(_anna.Id).Entries);
        Assert.Equal(95, after.Percent);
        Assert.Equal(before.Id, after.Id);
        Assert.Equal(before.Seq, after.Seq);
        Assert.True(after.Read);
        Assert.Equal(2, _push.Delivered.Count);
        // L'app ricarica la cassetta per mostrare la percentuale nuova.
        Assert.Single(_server.SentTo("s-anna"));

        // Senza cambi niente scrittura né avviso.
        await _alerts.SyncAsync("quota", [new("quota", InboxEntryTypes.DiskAlmostFull, "Disco", Percent: 95)]);
        Assert.Single(_server.SentTo("s-anna"));
    }

    [Fact]
    public async Task Raise_AddsToEveryEnabledAdminOnly()
    {
        var spento = _server.AddUser("Spento", enabled: false, isAdmin: true);
        var utente = _server.AddUser("Utente");
        var alert = new AdminAlert("stalled:1:1", InboxEntryTypes.DownloadStalled, "Dune");

        await _alerts.RaiseAsync(alert);
        await _alerts.RaiseAsync(alert);

        Assert.Equal(2, _inbox.Get(_anna.Id).Entries.Count);
        Assert.Equal(2, _inbox.Get(_bruno.Id).Entries.Count);
        Assert.Empty(_inbox.Get(spento.Id).Entries);
        Assert.Empty(_inbox.Get(utente.Id).Entries);
        Assert.Equal(4, _push.Delivered.Count);
        Assert.All(_push.Delivered, d => Assert.Equal(InboxEntryTypes.DownloadStalled, d.Entry.Type));
    }

    [Fact]
    public async Task Sync_NewAdminGetsCurrentAlerts()
    {
        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);
        var carla = _server.AddUser("Carla", isAdmin: true);

        await _alerts.SyncAsync("download:", [NeedsYou("download:1")]);

        Assert.Equal("download:1", Assert.Single(_inbox.Get(carla.Id).Entries).AlertKey);
        Assert.Equal(3, _push.Delivered.Count);
        Assert.Equal(carla.Id, _push.Delivered[^1].UserId);
    }
}
