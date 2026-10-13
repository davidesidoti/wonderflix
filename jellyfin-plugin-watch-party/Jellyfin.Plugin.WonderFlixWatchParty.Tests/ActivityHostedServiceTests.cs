using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ISessionManager _manager;
    private readonly InterfaceStub<ISessionManager> _stub;
    private EventHandler<PlaybackProgressEventArgs>? _start;
    private EventHandler<PlaybackProgressEventArgs>? _progress;
    private EventHandler<PlaybackStopEventArgs>? _stopped;

    public ActivityHostedServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        (_manager, _stub) = InterfaceStub<ISessionManager>.Create();
        _stub.Handlers["add_PlaybackStart"] = args => { _start = (EventHandler<PlaybackProgressEventArgs>?)args[0]; return null; };
        _stub.Handlers["add_PlaybackProgress"] = args => { _progress = (EventHandler<PlaybackProgressEventArgs>?)args[0]; return null; };
        _stub.Handlers["add_PlaybackStopped"] = args => { _stopped = (EventHandler<PlaybackStopEventArgs>?)args[0]; return null; };
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private T Args<T>(UserRef user, Guid movieId, TimeSpan position)
        where T : PlaybackProgressEventArgs, new() => new T
    {
        Session = new SessionInfo(_manager, NullLogger.Instance) { Id = "s-" + user.Name, Client = "WonderFlix", UserId = user.Id },
        Item = new Movie { Id = movieId },
        PlaybackPositionTicks = position.Ticks,
    };

    [Fact]
    public async Task ReportsAreRecordedAndTheTimerCleansUp()
    {
        var mario = _server.AddUser("Mario");
        var activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        using var hosted = new ActivityHostedService(_manager, activity, _time, NullLogger<ActivityHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.NotNull(_start);
        Assert.NotNull(_progress);
        Assert.NotNull(_stopped);

        var dune = Guid.NewGuid();
        _progress(_manager, Args<PlaybackProgressEventArgs>(mario, dune, TimeSpan.FromMinutes(6)));
        Assert.Equal(dune, Assert.Single(TestActivity.Saved(_folder, mario.Id)).ItemId);

        _server.Users.Remove(mario.Id);
        _time.Advance(ActivityHostedService.CleanupInterval);
        Assert.Empty(TestActivity.Saved(_folder, mario.Id));

        await hosted.StopAsync(CancellationToken.None);
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackStart");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackProgress");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackStopped");
    }

    [Fact]
    public async Task StartAndStopTellTheFriends()
    {
        var mario = _server.AddUser("Mario");
        var luigi = _server.AddUser("Luigi");
        await TestRecommendations.MakeFriendsAsync(_friends, mario.Id, luigi.Id);
        _server.AddSession("s-luigi", luigi);
        var activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        using var hosted = new ActivityHostedService(_manager, activity, _time, NullLogger<ActivityHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        var friendsChanged = JsonSerializer.Serialize(SocialEvent.FriendsChanged());
        _server.Sent.Clear();

        _start!(_manager, Args<PlaybackProgressEventArgs>(mario, Guid.NewGuid(), TimeSpan.Zero));
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { friendsChanged }, _server.SentTo("s-luigi"));

        _server.Sent.Clear();
        _stopped!(_manager, Args<PlaybackStopEventArgs>(mario, Guid.NewGuid(), TimeSpan.FromMinutes(1)));
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { friendsChanged }, _server.SentTo("s-luigi"));

        await hosted.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task AFailingReportDoesNotReachJellyfin()
    {
        var mario = _server.AddUser("Mario");

        // Un percorso con un carattere nullo: il salvataggio lancia ArgumentException, che Persist non prende.
        var store = new ActivityStore(Path.Combine(_folder.Path, "rotto\0", "activity.json"), NullLogger<ActivityStore>.Instance);
        var activity = new ActivityService(
            store, _friends, _server, _server, _server, new PartyRegistry(), _server, _server, _presence, _time,
            NullLogger<ActivityService>.Instance);
        var logger = new RecordingLogger<ActivityHostedService>();
        using var hosted = new ActivityHostedService(_manager, activity, _time, logger);
        await hosted.StartAsync(CancellationToken.None);

        var error = Record.Exception(() => _progress!(_manager, Args<PlaybackProgressEventArgs>(mario, Guid.NewGuid(), TimeSpan.FromMinutes(6))));

        Assert.Null(error);
        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
        await hosted.StopAsync(CancellationToken.None);
    }
}
