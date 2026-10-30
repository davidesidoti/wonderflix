using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.AspNetCore.Authorization;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InfoControllerTests
{
    private static FakeArrSettings NoArr() => new() { Sonarr = ArrEndpoint.None, Radarr = ArrEndpoint.None };

    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController(new FakeSeerrSettings { Url = string.Empty }, NoArr()).GetInfo().Value!;
        Assert.Equal("1.16.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home", "recommendations", "friendsActivity", "match", "ratings", "reports" },
            info.Features);
    }

    [Fact]
    public void RequestsAndUpcomingAppearOnlyWhenConfigured()
    {
        Assert.Equal(
            new[]
            {
                "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home", "recommendations", "friendsActivity", "match", "ratings", "reports",
                "requests", "upcomingSeries", "upcomingMovies", "calendar", "downloads", "space",
            },
            new InfoController(new FakeSeerrSettings(), new FakeArrSettings()).GetInfo().Value!.Features);

        var features = new InfoController(
                new FakeSeerrSettings { ApiKey = " " }, new FakeArrSettings { Sonarr = ArrEndpoint.None })
            .GetInfo().Value!.Features;
        Assert.DoesNotContain("requests", features);
        Assert.DoesNotContain("upcomingSeries", features);
        Assert.Contains("upcomingMovies", features);
        Assert.Contains("calendar", features);
        Assert.Contains("downloads", features);
        Assert.Contains("space", features);
    }

    [Fact]
    public void CalendarFollowsTheUpcomingFeaturesAndNeedsOneOfThem()
    {
        var onlySonarr = new InfoController(new FakeSeerrSettings(), new FakeArrSettings { Radarr = ArrEndpoint.None })
            .GetInfo().Value!.Features;
        Assert.Equal(new[] { "requests", "upcomingSeries", "calendar", "downloads", "space" }, onlySonarr.Skip(13));

        var neither = new InfoController(new FakeSeerrSettings(), NoArr()).GetInfo().Value!.Features;
        Assert.DoesNotContain("calendar", neither);
        Assert.DoesNotContain("downloads", neither);
        Assert.DoesNotContain("space", neither);
    }

    [Fact]
    public void InfoIsForEveryAuthenticatedUser()
    {
        // Nessuna policy: basta essere autenticati, anche senza accesso ai
        // watch party (la cassetta delle notifiche vale per tutti).
        var authorize = Assert.Single(typeof(InfoController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(InfoController).GetMethod(nameof(InfoController.GetInfo))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }
}
