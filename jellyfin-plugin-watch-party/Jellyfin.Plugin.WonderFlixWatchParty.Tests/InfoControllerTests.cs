using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Microsoft.AspNetCore.Authorization;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InfoControllerTests
{
    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController(new FakeSeerrSettings { Url = string.Empty }).GetInfo().Value!;
        Assert.Equal("1.4.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties", "inbox", "queue" }, info.Features);
    }

    [Fact]
    public void RequestsAppearOnlyWithSeerrConfigured()
    {
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "requests" },
            new InfoController(new FakeSeerrSettings()).GetInfo().Value!.Features);
        Assert.DoesNotContain(
            "requests", new InfoController(new FakeSeerrSettings { ApiKey = " " }).GetInfo().Value!.Features);
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
