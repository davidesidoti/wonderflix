using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ServerAlertsHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeServer _server = new();
    private readonly FakeRestartState _restart = new();
    private readonly RecordingPush _push = new();
    private readonly InboxService _inbox;
    private readonly ServerAlertsHostedService _service;
    private readonly UserRef _anna;

    public ServerAlertsHostedServiceTests()
    {
        _anna = _server.AddUser("Anna", isAdmin: true);
        _inbox = TestInbox.Create(_server, _folder, _time, _push);
        var alerts = new AdminAlerts(_inbox, _server, _time, NullLogger<AdminAlerts>.Instance);
        _service = new ServerAlertsHostedService(_restart, alerts, _time, NullLogger<ServerAlertsHostedService>.Instance);
    }

    public void Dispose()
    {
        _service.Dispose();
        _folder.Dispose();
    }

    private sealed class FakeRestartState : IRestartState
    {
        public bool PendingRestart { get; set; }
    }

    private sealed class RecordingPush : IInboxPush
    {
        public List<(Guid UserId, InboxEntry Entry)> Delivered { get; } = [];

        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh) => Delivered.AddRange(fresh);
    }

    private static async Task<bool> Eventually(Func<bool> condition)
    {
        for (var i = 0; i < 100 && !condition(); i++)
        {
            await Task.Delay(50);
        }

        return condition();
    }

    [Fact]
    public async Task Pending_RaisesOnce()
    {
        _restart.PendingRestart = true;

        await _service.CheckAsync();
        await _service.CheckAsync();

        var entry = Assert.Single(_inbox.Get(_anna.Id).Entries);
        Assert.Equal(InboxEntryTypes.RestartPending, entry.Type);
        Assert.Equal("restart", entry.AlertKey);
        Assert.Equal("Jellyfin", entry.Title);
        Assert.Single(_push.Delivered);
    }

    [Fact]
    public async Task NotPending_RaisesNothing()
    {
        await _service.CheckAsync();

        Assert.Empty(_inbox.Get(_anna.Id).Entries);
        Assert.Empty(_push.Delivered);
    }

    [Fact]
    public async Task NoLongerPending_Removes()
    {
        _restart.PendingRestart = true;
        await _service.CheckAsync();

        _restart.PendingRestart = false;
        await _service.CheckAsync();

        Assert.Empty(_inbox.Get(_anna.Id).Entries);
    }

    [Fact]
    public async Task PendingAgain_PushesAgain()
    {
        _restart.PendingRestart = true;
        await _service.CheckAsync();
        _restart.PendingRestart = false;
        await _service.CheckAsync();

        _restart.PendingRestart = true;
        await _service.CheckAsync();

        Assert.Single(_inbox.Get(_anna.Id).Entries);
        Assert.Equal(2, _push.Delivered.Count);
    }

    [Fact]
    public async Task TheTimerChecksAfterTheFirstRunThenEveryInterval()
    {
        _restart.PendingRestart = true;
        await _service.StartAsync(CancellationToken.None);

        await Task.Run(() => _time.Advance(ServerAlertsHostedService.FirstRun - TimeSpan.FromSeconds(1)));
        Assert.Empty(_inbox.Get(_anna.Id).Entries);

        await Task.Run(() => _time.Advance(TimeSpan.FromSeconds(1)));
        Assert.True(await Eventually(() => _inbox.Get(_anna.Id).Entries.Count == 1));

        _restart.PendingRestart = false;
        await Task.Run(() => _time.Advance(ServerAlertsHostedService.Interval));
        Assert.True(await Eventually(() => _inbox.Get(_anna.Id).Entries.Count == 0));

        await _service.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task AFailureDoesNotThrow()
    {
        var failing = new FailingRestartState();
        var alerts = new AdminAlerts(_inbox, _server, _time, NullLogger<AdminAlerts>.Instance);
        using var service = new ServerAlertsHostedService(failing, alerts, _time, NullLogger<ServerAlertsHostedService>.Instance);

        await service.CheckAsync();

        Assert.Empty(_inbox.Get(_anna.Id).Entries);
    }

    private sealed class FailingRestartState : IRestartState
    {
        public bool PendingRestart => throw new InvalidOperationException("host");
    }
}
