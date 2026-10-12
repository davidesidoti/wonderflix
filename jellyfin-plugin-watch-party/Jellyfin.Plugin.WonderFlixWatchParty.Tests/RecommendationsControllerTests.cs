using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly RecommendationService _service;
    private readonly RecommendableItem _dune;

    public RecommendationsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        TestRecommendations.MakeFriendsAsync(friends, _mario.Id, _luigi.Id).GetAwaiter().GetResult();
        _service = TestRecommendations.Create(_server, _folder, _time, friends);
        _dune = _server.AddRecommendable("Dune", 2021);
    }

    public void Dispose() => _folder.Dispose();

    private RecommendationsController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new RecommendationsController(new FakeAuthorizationContext(auth), _service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    private static string N(Guid id) => id.ToString("N");

    [Fact]
    public async Task RecommendListAndDismiss()
    {
        var targets = (await Controller(_mario).GetTargets(N(_dune.Id))).Value!;
        Assert.Equal("Luigi", Assert.Single(targets.Friends).Name);

        var sent = (await Controller(_mario).Recommend(new RecommendRequest
        {
            ItemId = N(_dune.Id), To = [N(_luigi.Id)], Message = "da vedere",
        })).Value!;
        Assert.Equal(1, sent.Sent);

        var item = Assert.Single((await Controller(_luigi).GetRecommendations()).Value!.Items);
        Assert.Equal("Mario", Assert.Single(item.From).Name);

        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).Dismiss(N(_dune.Id))));
        Assert.Empty((await Controller(_luigi).GetRecommendations()).Value!.Items);

        // Mai 404: un id che non c'è, o che non è un id, dà 204.
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).Dismiss("non-un-id")));
    }

    [Fact]
    public async Task BadRequestsAre400AndTooManyAre429()
    {
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).GetTargets("non-un-id")).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).GetTargets(null)).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).Recommend(null)).Result!));
        Assert.Equal(
            StatusCodes.Status400BadRequest,
            Status((await Controller(_mario).Recommend(new RecommendRequest
            {
                ItemId = N(_dune.Id), To = [N(_luigi.Id)], Message = new string('a', 201),
            })).Result!));

        for (var i = 0; i < 30; i++)
        {
            await Controller(_mario).Recommend(new RecommendRequest { ItemId = N(_dune.Id), To = [N(_luigi.Id)] });
        }

        Assert.Equal(
            StatusCodes.Status429TooManyRequests,
            Status((await Controller(_mario).Recommend(new RecommendRequest { ItemId = N(_dune.Id), To = [N(_luigi.Id)] })).Result!));
    }

    [Fact]
    public void TheControllerNeedsWatchPartyAccessAndNeverRouteConstraints()
    {
        Assert.Equal(
            Policies.SyncPlayHasAccess,
            Assert.Single(typeof(RecommendationsController).GetCustomAttributes<AuthorizeAttribute>()).Policy);
        // La riflessione non garantisce l'ordine dei metodi: si confrontano gli elenchi ordinati.
        var routes = typeof(RecommendationsController).GetMethods()
            .SelectMany(m => m.GetCustomAttributes<Microsoft.AspNetCore.Mvc.Routing.HttpMethodAttribute>())
            .Select(a => a.Template)
            .Order(StringComparer.Ordinal)
            .ToList();
        Assert.Equal(
            new[] { "Recommendations", "Recommendations", "Recommendations/Targets", "Recommendations/{itemId}" },
            routes);
    }
}
