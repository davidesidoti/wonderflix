using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingControllerTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 10, 14, 30, 0, TimeSpan.Zero);

    private readonly User _mario = new("mario", "provider", "reset");
    private readonly FakeArrClient _client = new();
    private readonly FakeSeriesIndex _index = new();

    private UpcomingController Controller()
    {
        var (library, stub) = InterfaceStub<ILibraryAccess>.Create();
        stub.Handlers["CanSee"] = args => (Guid)args[0]! == _mario.Id;
        var service = new UpcomingService(
            _client, new FakeArrSettings(), _index, library, new FakeTimeProvider(Now), new RecordingLogger<UpcomingService>());
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new UpcomingController(new FakeAuthorizationContext(auth), service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task SeriesAreReadForTheCaller()
    {
        var bear = Guid.NewGuid();
        _index.Series.Add(new LibrarySeries(bear, "136311", null, null));
        _client.Episodes = (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
        [
            new SonarrEpisode
            {
                SeriesId = 1,
                SeasonNumber = 1,
                EpisodeNumber = 1,
                AirDateUtc = Now.AddDays(1),
                Series = new SonarrSeries { Title = "The Bear", TvdbId = 136311 },
            },
        ]);

        var answer = (await Controller().GetSeries()).Value!;

        Assert.Equal(bear.ToString("N"), Assert.Single(answer.Items).JellyfinSeriesId);
    }

    [Fact]
    public async Task MoviesAndTheTest()
    {
        Assert.Null((await Controller().GetMovies()).Value!.Error);

        var test = (await Controller().Test()).Value!;
        Assert.True(test.Sonarr.Ok);
        Assert.True(test.Radarr.Ok);
    }

    [Fact]
    public void EveryoneReadsOnlyAdminsTest()
    {
        var authorize = Assert.Single(typeof(UpcomingController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(UpcomingController).GetMethod(nameof(UpcomingController.GetSeries))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Empty(typeof(UpcomingController).GetMethod(nameof(UpcomingController.GetMovies))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            Policies.RequiresElevation,
            Assert.Single(typeof(UpcomingController).GetMethod(nameof(UpcomingController.Test))!
                .GetCustomAttributes<AuthorizeAttribute>()).Policy);
    }
}
