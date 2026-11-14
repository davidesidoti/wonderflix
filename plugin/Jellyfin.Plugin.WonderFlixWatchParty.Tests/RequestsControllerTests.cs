using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RequestsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeSeerrSettings _settings = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly RequestsService _service;
    private readonly RequestWebhookHandler _webhook;
    private readonly SeerrRequestList _list;
    private readonly ListReadingPush _push = new();

    public RequestsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, false);
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = _mario.Id.ToString("N") });
        var map = new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance);
        _service = new RequestsService(_seerr, map, new SeerrTitleCache(_seerr, _time), _list = new SeerrRequestList(_seerr, _time), new ReleaseDatesService(new FakeArrClient(), new FakeArrSettings { Sonarr = ArrEndpoint.None, Radarr = ArrEndpoint.None }, _time, NullLogger<ReleaseDatesService>.Instance), TestDownloads.Create(new FakeArrClient()), _time);
        _webhook = new RequestWebhookHandler(
            _settings, map, _list, _server, TestInbox.Create(_server, _folder, _time, _push), _time,
            NullLogger<RequestWebhookHandler>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    /// <summary>Alla push della cassetta legge l'elenco delle richieste di Mario, come farebbe l'app.</summary>
    private sealed class ListReadingPush : IInboxPush
    {
        public Func<Task<IReadOnlyList<SeerrRequest>>>? Read { get; set; }

        public Task<IReadOnlyList<SeerrRequest>>? ReadAtPush { get; private set; }

        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh) => ReadAtPush = Read?.Invoke();
    }

    private RequestsController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new RequestsController(new FakeAuthorizationContext(auth), _service, _settings, _seerr, _webhook)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status<T>(ActionResult<T> result) => result.Result switch
    {
        null => StatusCodes.Status200OK,
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException("risultato inatteso"),
    };

    private static string? Code<T>(ActionResult<T> result) =>
        ((result.Result as ObjectResult)?.Value as RequestsErrorDto)?.Code;

    [Fact]
    public async Task MeIsForTheCaller()
    {
        var me = await Controller().Me();

        Assert.Equal(new RequestsMeResponse(true, false, true), me.Value);
    }

    [Fact]
    public async Task ACallerWithoutAUserIsRefusedBeforeAnyCallToSeerr()
    {
        // Per esempio una chiave API di Jellyfin: autenticata ma senza utente.
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", IsAuthenticated = true };
        var controller = new RequestsController(new FakeAuthorizationContext(auth), _service, _settings, _seerr, _webhook)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

        var me = await controller.Me();

        Assert.Equal((403, "NoPermission"), (Status(me), Code(me)));
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task WithoutSeerrEveryEndpointSaysNotConfigured()
    {
        _settings.Url = string.Empty;

        var me = await Controller().Me();
        var search = await Controller().Search("dune", "it");

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(me));
        Assert.Equal("NotConfigured", Code(me));
        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(search));
        Assert.Empty(_seerr.Calls);
    }

    [Theory]
    [InlineData(SeerrError.NotConfigured, 503, "NotConfigured")]
    [InlineData(SeerrError.Unavailable, 502, "SeerrUnavailable")]
    [InlineData(SeerrError.Auth, 502, "SeerrAuth")]
    [InlineData(SeerrError.NoPermission, 403, "NoPermission")]
    [InlineData(SeerrError.QuotaExceeded, 403, "QuotaExceeded")]
    [InlineData(SeerrError.Blocklisted, 403, "Blocklisted")]
    [InlineData(SeerrError.AlreadyRequested, 409, "AlreadyRequested")]
    [InlineData(SeerrError.NothingToRequest, 409, "NothingToRequest")]
    [InlineData(SeerrError.AccountUnavailable, 409, "AccountUnavailable")]
    [InlineData(SeerrError.NotFound, 400, "UnknownRequest")]
    [InlineData(SeerrError.BadRequest, 400, "Invalid")]
    public void SeerrErrorsBecomeStatusAndCode(SeerrError error, int status, string code)
    {
        var result = RequestsController.Error(error);

        Assert.Equal(status, result.StatusCode);
        Assert.Equal(new RequestsErrorDto(code), result.Value);
    }

    [Fact]
    public async Task SeerrDownAndBadIdsAreErrorsNever404()
    {
        var badId = await Controller().Movie("abc", "it");
        var zero = await Controller().Tv("0", "it");
        var unknown = await Controller().Movie("5", "it");
        _seerr.FailWith = SeerrError.Unavailable;
        var down = await Controller().Search("dune", "it");

        Assert.Equal((400, "Invalid"), (Status(badId), Code(badId)));
        Assert.Equal((400, "Invalid"), (Status(zero), Code(zero)));
        Assert.Equal((400, "UnknownRequest"), (Status(unknown), Code(unknown)));
        Assert.Equal((502, "SeerrUnavailable"), (Status(down), Code(down)));
    }

    [Fact]
    public async Task CreateListAndManagerEndpoints()
    {
        var created = await Controller().Create(new CreateRequestBody { MediaType = "movie", TmdbId = 841 });
        var mine = await Controller().List("mine", null, null, "it");
        var pending = await Controller().List("pending", null, null, "it");
        var services = await Controller().Services("movie");
        var approve = await Controller().Approve("53", null, "it");

        Assert.Equal(new CreatedRequestDto(100, RequestStatuses.Pending), created.Value);
        Assert.Equal((24, "all", RequestsController.DefaultTake, 0, (int?)24), Assert.Single(_seerr.Listed));
        Assert.NotNull(mine.Value);
        Assert.Equal((403, "NoPermission"), (Status(pending), Code(pending)));
        Assert.Equal((403, "NoPermission"), (Status(services), Code(services)));
        Assert.Equal((403, "NoPermission"), (Status(approve), Code(approve)));
    }

    [Fact]
    public async Task ListPassesTheGroup()
    {
        _seerr.Requests.Add(new SeerrRequest
        {
            Id = 53, Status = SeerrCodes.RequestCompleted, Type = "movie",
            Media = new SeerrRequestMedia { TmdbId = 841, MediaType = "movie", Status = SeerrCodes.MediaAvailable },
        });

        var done = await Controller().List("mine", null, null, "it", "done");
        var open = await Controller().List("mine", null, null, "it", "open");
        var bad = await Controller().List("mine", null, null, "it", "altro");

        Assert.Equal((1, 53), (done.Value!.Total, Assert.Single(done.Value.Items).Id));
        Assert.Equal(0, open.Value!.Total);
        Assert.Equal((400, "Invalid"), (Status(bad), Code(bad)));
    }

    [Fact]
    public async Task WebhookClearsTheListBeforeTheInbox()
    {
        SeerrRequest Dune(int status) => new()
        {
            Id = 53, Status = status, Type = "movie",
            RequestedBy = new SeerrRequestUser { Id = 24 },
            Media = new SeerrRequestMedia { TmdbId = 438631, MediaType = "movie", Status = SeerrCodes.MediaProcessing },
        };
        _seerr.Requests.Add(Dune(SeerrCodes.RequestApproved));
        Assert.Equal(0, (await Controller().List("mine", null, null, "it", "done")).Value!.Total);

        // Seerr ha finito: un oggetto nuovo, l'elenco in memoria tiene il vecchio.
        _seerr.Requests[0] = Dune(SeerrCodes.RequestCompleted);
        _push.Read = () => _list.GetAsync(24, 24, CancellationToken.None);
        await _webhook.HandleAsync(
            new SeerrWebhookPayload
            {
                Secret = "secret", NotificationType = RequestWebhookHandler.MediaAvailable, Subject = "Dune (2021)",
                RequestId = "53", MediaType = "movie", MediaTmdbId = "438631",
                RequestedByJellyfinUserId = _mario.Id.ToString("N"),
            },
            CancellationToken.None);

        // Già alla push dell'avviso l'elenco è quello nuovo.
        Assert.NotNull(_push.ReadAtPush);
        Assert.Equal(SeerrCodes.RequestCompleted, Assert.Single(await _push.ReadAtPush!).Status);
        Assert.Equal(1, (await Controller().List("mine", null, null, "it", "done")).Value!.Total);
        Assert.Equal(2, _seerr.Listed.Count);
    }

    [Fact]
    public async Task TestSaysVersionOrWhatIsWrong()
    {
        var ok = await Controller().Test();
        _seerr.FailOn["GetMe"] = SeerrError.Auth;
        var badKey = await Controller().Test();
        _seerr.FailOn.Clear();
        _seerr.FailWith = SeerrError.Unavailable;
        var down = await Controller().Test();
        _settings.ApiKey = string.Empty;
        var unset = await Controller().Test();

        Assert.Equal(new SeerrTestResponse(true, "3.4.1", null), ok.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "SeerrAuth"), badKey.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "SeerrUnavailable"), down.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "NotConfigured"), unset.Value);
    }

    [Fact]
    public async Task AdminShowsTheLastWebhookEvent()
    {
        Assert.Equal(new RequestsAdminStatus(true, null, null), Controller().Admin().Value);

        await _webhook.HandleAsync(new SeerrWebhookPayload { Secret = "secret", NotificationType = "TEST_NOTIFICATION" }, CancellationToken.None);

        Assert.Equal(new RequestsAdminStatus(true, _time.GetUtcNow(), "TEST_NOTIFICATION"), Controller().Admin().Value);
    }

    [Fact]
    public async Task TheWebhookAnswers401OnlyForAWrongSecret()
    {
        var controller = new RequestsWebhookController(_webhook)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

        Assert.IsType<UnauthorizedResult>(await controller.Receive(new SeerrWebhookPayload { Secret = "no" }));
        Assert.IsType<OkResult>(await controller.Receive(new SeerrWebhookPayload { Secret = "secret", NotificationType = "TEST_NOTIFICATION" }));
    }

    [Fact]
    public void AuthorizationAndRoutes()
    {
        var authorize = Assert.Single(typeof(RequestsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        foreach (var name in new[] { nameof(RequestsController.Test), nameof(RequestsController.Admin) })
        {
            Assert.Equal(
                Policies.RequiresElevation,
                Assert.Single(typeof(RequestsController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>()).Policy);
        }

        Assert.NotNull(typeof(RequestsWebhookController).GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.NotNull(typeof(RequestsWebhookController).GetMethod(nameof(RequestsWebhookController.Receive))!
            .GetCustomAttribute<RequestSizeLimitAttribute>());

        // Nessun vincolo di tipo nelle rotte: un id sbagliato darebbe 404.
        var templates = typeof(RequestsController).GetMethods()
            .SelectMany(m => m.GetCustomAttributes<HttpMethodAttribute>())
            .Select(a => a.Template ?? string.Empty);
        Assert.DoesNotContain(templates, t => t.Contains(':', StringComparison.Ordinal));
    }
}
