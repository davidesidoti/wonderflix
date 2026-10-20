using System.Reflection;
using System.Text.Json;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 20, 21, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly User _toad = new("toad", "provider", "reset");
    private readonly RatingService _ratings;
    private readonly RatingRoundService _rounds;
    private readonly Guid _group = Guid.NewGuid();
    private readonly RatedTitle _film;

    public RatingsControllerTests()
    {
        foreach (var user in new[] { _mario, _luigi, _toad })
        {
            var reference = new UserRef(user.Id, user.Username, true, true);
            _server.Users[user.Id] = reference;
            _server.AddSession("s-" + user.Username, reference);
        }

        _server.Groups[_group] = ["mario", "luigi"];
        _film = _server.AddRated("Il Padrino (1972)");
        _server.RoundTargets[_film.Id] = _film.Id;
        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        var parties = new PartyDirectory(_time);
        parties.Register(_group, _mario.Id, PartyModes.Friends);
        _ratings = TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
        _rounds = TestRatings.Rounds(_server, _ratings, _time, parties);
    }

    public void Dispose()
    {
        _rounds.Dispose();
        _folder.Dispose();
    }

    private static AuthorizationInfo Auth(User user) =>
        new() { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };

    private RatingsController Controller(User user) =>
        new(new FakeAuthorizationContext(Auth(user)), _ratings, _rounds)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    private RatingsAdminController Admin(User user) =>
        new(new FakeAuthorizationContext(Auth(user)), _ratings)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    private static string N(Guid id) => id.ToString("N");

    [Fact]
    public async Task RoundEndpointsMapTheOutcomes()
    {
        var open = await Controller(_mario).OpenRound(new OpenRatingRoundRequest { GroupId = N(_group), ItemId = N(_film.Id) });
        Assert.IsType<RatingRoundDto>(Assert.IsType<OkObjectResult>(open.Result).Value);

        var empty = Assert.IsType<OkObjectResult>((await Controller(_toad).GetRound(N(_group))).Result);
        Assert.IsType<RatingRoundEmptyDto>(empty.Value);
        Assert.Equal("{}", JsonSerializer.Serialize(empty.Value));
        Assert.Equal("{}", JsonSerializer.Serialize(new RatingRoundEmptyDto()));

        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).GetRound("abc")).Result!));

        var conflict = Assert.IsType<ObjectResult>((await Controller(_luigi).RevealRound(N(_group))).Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal(new RatingErrorDto("NotCreator"), conflict.Value);

        var bad = await Controller(_mario).VoteInRound(N(_group), new RateRequest { Score = 0 });
        Assert.Equal(StatusCodes.Status400BadRequest, Status(bad.Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).SkipRound("abc")).Result!));
    }

    [Fact]
    public async Task RatingsEndpointsMapTheOutcomes()
    {
        var controller = Controller(_mario);
        Assert.IsType<ItemRatingsDto>((await controller.GetRatings(N(_film.Id))).Value);
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await controller.GetRatings("abc")).Result!));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.Rate(N(_film.Id), new RateRequest { Score = 8 })));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.DeleteRating(N(_film.Id))));

        // 2 scritture fatte: altre 58 stanno nel limite, la 61esima no.
        for (var i = 0; i < 58; i++)
        {
            Assert.Equal(StatusCodes.Status204NoContent, Status(await controller.Rate(N(_film.Id), new RateRequest { Score = 8 })));
        }

        Assert.Equal(StatusCodes.Status429TooManyRequests, Status(await controller.Rate(N(_film.Id), new RateRequest { Score = 8 })));
    }

    [Fact]
    public async Task AdminEndpoints()
    {
        var admin = Admin(_mario);
        Assert.IsType<AdminCommentsDto>(admin.GetComments(null).Value);
        Assert.Equal(StatusCodes.Status400BadRequest, Status(admin.GetComments("ieri").Result!));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await admin.DeleteComment(N(_luigi.Id), N(_film.Id))));
        Assert.Equal(StatusCodes.Status400BadRequest, Status(await admin.DeleteComment("x", "y")));
    }

    [Fact]
    public void PoliciesAndNoRouteConstraints()
    {
        var ratings = Assert.Single(typeof(RatingsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.SyncPlayHasAccess, ratings.Policy);

        var admin = Assert.Single(typeof(RatingsAdminController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(admin.Policy);
        foreach (var name in new[] { nameof(RatingsAdminController.GetComments), nameof(RatingsAdminController.DeleteComment) })
        {
            var method = Assert.Single(typeof(RatingsAdminController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>());
            Assert.Equal(Policies.RequiresElevation, method.Policy);
        }

        var templates = new[] { typeof(RatingsController), typeof(RatingsAdminController) }
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
            .SelectMany(m => m.GetCustomAttributes<HttpMethodAttribute>())
            .Select(a => a.Template!)
            .ToList();
        Assert.DoesNotContain(templates, t => t.Contains(':'));
        Assert.Equal(
            new[]
            {
                "Ratings", "Ratings/Admin/Comments", "Ratings/Admin/Comments/{userId}/{itemId}", "Ratings/Rounds",
                "Ratings/Rounds/{groupId}", "Ratings/Rounds/{groupId}/Reveal", "Ratings/Rounds/{groupId}/Skip",
                "Ratings/Rounds/{groupId}/Vote", "Ratings/{itemId}", "Ratings/{itemId}",
            },
            templates.Order(StringComparer.Ordinal));
    }
}
