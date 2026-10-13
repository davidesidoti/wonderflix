using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _activity;

    public ActivityControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private ActivityController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new ActivityController(new FakeAuthorizationContext(auth), _activity)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task SharingIsOnUntilTurnedOff()
    {
        Assert.True((await Controller(_mario).GetSettings()).Value!.ShareActivity);

        Assert.IsType<NoContentResult>(await Controller(_mario).SetSettings(new ActivitySettings { ShareActivity = false }));
        Assert.False((await Controller(_mario).GetSettings()).Value!.ShareActivity);
        Assert.True((await Controller(_luigi).GetSettings()).Value!.ShareActivity);

        Assert.IsType<NoContentResult>(await Controller(_mario).SetSettings(new ActivitySettings { ShareActivity = true }));
        Assert.True((await Controller(_mario).GetSettings()).Value!.ShareActivity);
    }

    [Fact]
    public async Task AMissingChoiceIs400()
    {
        Assert.IsType<BadRequestResult>(await Controller(_mario).SetSettings(null));
        Assert.IsType<BadRequestResult>(await Controller(_mario).SetSettings(new ActivitySettings()));
    }

    [Fact]
    public async Task FriendsWatchedListsTheFriendsViews()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var dune = Guid.NewGuid();
        _activity.Report(new PlaybackReport("s-luigi", _luigi.Id, dune, TimeSpan.FromMinutes(6).Ticks, false), stopped: false);

        var items = (await Controller(_mario).GetFriendsWatched()).Value!.Items;

        Assert.Equal(dune.ToString("N"), Assert.Single(items).ItemId);
    }
}
