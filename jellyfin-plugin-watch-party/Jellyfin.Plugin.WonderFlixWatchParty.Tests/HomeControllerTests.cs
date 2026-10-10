using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeControllerTests
{
    private readonly FakeHomeLayoutStore _store = new();

    private HomeController Controller() => new(_store);

    [Fact]
    public void WithoutAnAdminLayoutRowsAreNull()
    {
        Assert.Null(Controller().GetLayout().Value!.Rows);
    }

    [Fact]
    public void TheAdminLayoutIsSavedCleanAndReadBack()
    {
        var saved = Controller().SetLayout(
            new HomeLayoutRequest { Rows = ["upcomingMovies", "bogus", "resume", "upcomingMovies", null] });

        Assert.Equal(new[] { "upcomingMovies", "resume" }, saved.Value!.Rows);
        Assert.Equal(new[] { "upcomingMovies", "resume" }, _store.Rows);
        Assert.Equal(new[] { "upcomingMovies", "resume" }, Controller().GetLayout().Value!.Rows);
    }

    [Fact]
    public void AnEmptyListTurnsEveryRowOffAndNullGoesBackToTheDefault()
    {
        Assert.Empty(Controller().SetLayout(new HomeLayoutRequest { Rows = [] }).Value!.Rows!);
        Assert.Empty(_store.Rows!);

        Assert.Null(Controller().SetLayout(new HomeLayoutRequest { Rows = null }).Value!.Rows);
        Assert.Null(_store.Rows);
        Assert.Equal(2, _store.Saves);
    }

    [Fact]
    public void AMissingBodyIsABadRequestAndSavesNothing()
    {
        Assert.IsType<BadRequestResult>(Controller().SetLayout(null).Result);
        Assert.Equal(0, _store.Saves);
    }

    [Fact]
    public void EveryoneReadsOnlyAdminsWrite()
    {
        var authorize = Assert.Single(typeof(HomeController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(HomeController).GetMethod(nameof(HomeController.GetLayout))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            Policies.RequiresElevation,
            Assert.Single(typeof(HomeController).GetMethod(nameof(HomeController.SetLayout))!
                .GetCustomAttributes<AuthorizeAttribute>()).Policy);
    }

    private sealed class FakeHomeLayoutStore : IHomeLayoutStore
    {
        public IReadOnlyList<string>? Rows { get; private set; }

        public int Saves { get; private set; }

        public void Save(IReadOnlyList<string>? rows)
        {
            Rows = rows;
            Saves++;
        }
    }
}
