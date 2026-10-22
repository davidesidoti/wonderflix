using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class CollectionsControllerTests
{
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly FakeCollections _collections = new();

    private CollectionsController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new CollectionsController(new FakeAuthorizationContext(auth), _collections)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task ListsTheCallersCollectionsWithJellyfinIds()
    {
        var matrix = Guid.NewGuid();
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var created = new DateTime(2026, 5, 1, 10, 0, 0, DateTimeKind.Utc);
        _collections.Result =
        [
            new CollectionInfo(matrix, "Matrix - Collezione", "matrix - collezione", "tag1", created, [first, second]),
        ];

        var entry = Assert.Single((await Controller().GetCollections()).Value!.Collections);
        // Gli id come li dà Jellyfin all'app: 32 cifre esadecimali, senza trattini.
        Assert.Equal(matrix.ToString("N"), entry.Id);
        Assert.Equal("Matrix - Collezione", entry.Name);
        Assert.Equal("matrix - collezione", entry.SortName);
        Assert.Equal("tag1", entry.PrimaryImageTag);
        Assert.Equal(created, entry.DateCreated);
        Assert.Equal(new[] { first.ToString("N"), second.ToString("N") }, entry.ItemIds);
        Assert.Equal(new[] { _mario.Id }, _collections.Callers);
    }

    [Fact]
    public async Task CollectionsWithoutVisibleTitlesAreLeftOut()
    {
        _collections.Result =
        [
            new CollectionInfo(Guid.NewGuid(), "Vuota", "vuota", null, DateTime.UtcNow, []),
            new CollectionInfo(Guid.NewGuid(), "Alien", "alien", null, DateTime.UtcNow, [Guid.NewGuid()]),
        ];

        var entry = Assert.Single((await Controller().GetCollections()).Value!.Collections);
        Assert.Equal("Alien", entry.Name);
        Assert.Null(entry.PrimaryImageTag);
    }

    [Fact]
    public async Task NoCollectionsIsAnEmptyList()
    {
        Assert.Empty((await Controller().GetCollections()).Value!.Collections);
    }

    [Fact]
    public void EveryAuthenticatedUserCanAsk()
    {
        // Le saghe non dipendono dal watch party: nessuna policy.
        var authorize = Assert.Single(typeof(CollectionsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(CollectionsController).GetMethod(nameof(CollectionsController.GetCollections))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }

    private sealed class FakeCollections : ICollectionDirectory
    {
        public List<Guid> Callers { get; } = [];

        public IReadOnlyList<CollectionInfo> Result { get; set; } = [];

        public Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId)
        {
            Callers.Add(userId);
            return Task.FromResult(Result);
        }
    }
}
