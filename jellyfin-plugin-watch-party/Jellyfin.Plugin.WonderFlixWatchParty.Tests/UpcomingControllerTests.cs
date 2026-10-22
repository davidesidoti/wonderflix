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
    private readonly FakeTimeProvider _time = new(Now);

    private UpcomingController Controller()
    {
        var (library, stub) = InterfaceStub<ILibraryAccess>.Create();
        stub.Handlers["CanSee"] = args => (Guid)args[0]! == _mario.Id;
        var settings = new FakeArrSettings();
        var service = new UpcomingService(
            _client, settings, _index, library, _time, new RecordingLogger<UpcomingService>());
        var calendar = new CalendarService(
            _client, settings, _index, library, _time, new RecordingLogger<CalendarService>());
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new UpcomingController(new FakeAuthorizationContext(auth), service, calendar)
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
    public async Task TheCalendarIsReadForTheCaller()
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
                AirDateUtc = new DateTimeOffset(2026, 10, 12, 1, 0, 0, TimeSpan.Zero),
                Series = new SonarrSeries { Title = "The Bear", TvdbId = 136311 },
            },
        ]);

        var answer = (await Controller().GetCalendar("2026-10-01", "2026-11-01")).Value!;

        Assert.Equal(bear.ToString("N"), Assert.Single(answer.Episodes).JellyfinSeriesId);
        Assert.Null(answer.SeriesError);
        Assert.Empty(answer.Movies);
    }

    [Theory]
    [InlineData(null, "2026-11-01")]
    [InlineData("2026-10-1", "2026-11-01")]
    [InlineData("01/10/2026", "2026-11-01")]
    [InlineData("2026-10-01", "2026-10-01")]
    [InlineData("2026-10-01", "2026-11-13")]
    [InlineData("0001-01-01", "0001-01-02")]
    [InlineData("9999-12-30", "9999-12-31")]
    public async Task ABadPeriodIsABadRequest(string? start, string? end) =>
        Assert.IsType<BadRequestResult>((await Controller().GetCalendar(start, end)).Result);

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
