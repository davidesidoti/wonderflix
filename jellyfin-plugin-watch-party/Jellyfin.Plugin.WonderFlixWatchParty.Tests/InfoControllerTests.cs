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
        Assert.Equal("1.7.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home" },
            info.Features);
    }

    [Fact]
    public void RequestsAndUpcomingAppearOnlyWhenConfigured()
    {
        Assert.Equal(
            new[]
            {
                "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home",
                "requests", "upcomingSeries", "upcomingMovies",
            },
            new InfoController(new FakeSeerrSettings(), new FakeArrSettings()).GetInfo().Value!.Features);

        var features = new InfoController(
                new FakeSeerrSettings { ApiKey = " " }, new FakeArrSettings { Sonarr = ArrEndpoint.None })
            .GetInfo().Value!.Features;
        Assert.DoesNotContain("requests", features);
        Assert.DoesNotContain("upcomingSeries", features);
        Assert.Contains("upcomingMovies", features);
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
