using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityServiceTests : IDisposable
{
    private static readonly string FriendsChanged = JsonSerializer.Serialize(SocialEvent.FriendsChanged());

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _session;

    public ActivityServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _service = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _session = _server.AddSession("s-mario", _mario);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public void AViewIsRecordedAfterFiveMinutesOnce()
    {
        var dune = Guid.NewGuid();
        var start = _time.GetUtcNow();

        _service.Report(TestActivity.Report(_session, dune, ActivityService.MinWatch - TimeSpan.FromSeconds(1)), stopped: false);
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));

        _service.Report(TestActivity.Report(_session, dune, ActivityService.MinWatch), stopped: false);
        Assert.Equal(new[] { new WatchedTitle(dune, start) }, TestActivity.Saved(_folder, _mario.Id));

        // Altri resoconti e lo stop della stessa visione non riscrivono la data.
        _time.Advance(TimeSpan.FromMinutes(2));
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7)), stopped: false);
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(8)), stopped: true);
        Assert.Equal(new[] { new WatchedTitle(dune, start) }, TestActivity.Saved(_folder, _mario.Id));

        // Dopo lo stop, una nuova visione aggiorna la data.
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(9)), stopped: false);
        Assert.Equal(new[] { new WatchedTitle(dune, _time.GetUtcNow()) }, TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void AStopFromTheIdleCheckIsNotAWatch()
    {
        var dune = Guid.NewGuid();
        var staleCheckIn = _time.GetUtcNow() - ActivityService.MaxReportAge - TimeSpan.FromMinutes(5);

        // Jellyfin ha fatto avanzare la posizione da sé: l'app non riportava più da minuti.
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7), checkIn: staleCheckIn), stopped: true);
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));

        // Arrivato alla fine, invece, conta lo stesso.
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7), completed: true, checkIn: staleCheckIn), stopped: true);
        Assert.Single(TestActivity.Saved(_folder, _mario.Id));

        // Stesso stop con un resoconto recente: conta.
        var bear = Guid.NewGuid();
        _service.Report(TestActivity.Report(_session, bear, TimeSpan.FromMinutes(7), checkIn: _time.GetUtcNow() - TimeSpan.FromSeconds(10)), stopped: true);
        Assert.Contains(bear, TestActivity.Saved(_folder, _mario.Id).Select(v => v.ItemId));
    }

    [Fact]
    public void AFinishedOrLongStopIsRecorded()
    {
        var short1 = Guid.NewGuid();
        var finished = Guid.NewGuid();
        var longStop = Guid.NewGuid();

        _service.Report(TestActivity.Report(_session, short1, TimeSpan.FromMinutes(2)), stopped: true);
        _service.Report(TestActivity.Report(_session, finished, TimeSpan.FromMinutes(1), completed: true), stopped: true);
        _service.Report(TestActivity.Report(_session, longStop, ActivityService.MinWatch), stopped: true);

        var saved = TestActivity.Saved(_folder, _mario.Id).Select(v => v.ItemId).ToList();
        Assert.DoesNotContain(short1, saved);
        Assert.Contains(finished, saved);
        Assert.Contains(longStop, saved);
    }

    [Fact]
    public void AnEpisodeWithoutSeriesIsNotRecorded()
    {
        _service.Report(TestActivity.Report(_session, null, TimeSpan.FromMinutes(30)), stopped: false);
        _service.Report(TestActivity.Report(_session, null, TimeSpan.FromMinutes(40), completed: true), stopped: true);

        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void NothingIsRecordedWhileSharingIsOff()
    {
        Assert.True(_service.Shares(_mario.Id));
        _service.SetShare(_mario.Id, false);
        Assert.False(_service.Shares(_mario.Id));

        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(10)), stopped: false);
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));

        _service.SetShare(_mario.Id, true);
        var bear = Guid.NewGuid();
        _service.Report(TestActivity.Report(_session, bear, TimeSpan.FromMinutes(10)), stopped: false);
        Assert.Equal(bear, Assert.Single(TestActivity.Saved(_folder, _mario.Id)).ItemId);
    }

    [Fact]
    public async Task TurningSharingOffDeletesTheViewsAndTellsTheFriends()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        _server.AddSession("s-luigi", _luigi);
        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(10)), stopped: false);
        _server.Sent.Clear();

        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);

        Assert.Equal(new[] { FriendsChanged }, _server.SentTo("s-luigi"));
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
        Assert.False(new ActivityStore(_folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load().Shares(_mario.Id));

        // Già spenta: niente da dire agli amici.
        _server.Sent.Clear();
        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.SentTo("s-luigi"));
    }

    [Fact]
    public async Task PlaybackChangesTellTheFriendsOnlyWhenSharing()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        _server.AddSession("s-luigi", _luigi);
        _server.Sent.Clear();

        _service.PlaybackChanged(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { FriendsChanged }, _server.SentTo("s-luigi"));

        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);
        _server.Sent.Clear();

        _service.PlaybackChanged(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.SentTo("s-luigi"));
    }

    [Fact]
    public void CleanupDropsOldViewsAndForgetsEndedSessions()
    {
        var dune = Guid.NewGuid();
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(6)), stopped: false);

        // La sessione finisce senza stop: alla pulizia si dimentica, e una visione nuova si registra.
        _server.Sessions.Remove(_session);
        _time.Advance(TimeSpan.FromHours(1));
        Assert.Equal(0, _service.Cleanup());
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7)), stopped: false);
        Assert.Equal(_time.GetUtcNow(), Assert.Single(TestActivity.Saved(_folder, _mario.Id)).WatchedAt);

        _time.Advance(ActivityService.MaxAge + TimeSpan.FromMinutes(1));
        Assert.Equal(1, _service.Cleanup());
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void CleanupForgetsUsersThatNoLongerExist()
    {
        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
        _service.SetShare(_luigi.Id, false);
        _server.Users.Remove(_mario.Id);
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(2, _service.Cleanup());
        var saved = new ActivityStore(_folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load();
        Assert.Empty(saved.Views(_mario.Id));
        Assert.True(saved.Shares(_luigi.Id));
    }
}
