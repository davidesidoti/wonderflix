using System.Security.Cryptography;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NotificationsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakePushTransport _transport = new();
    private readonly FakeDeviceAccess _devices = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly PushService _push;
    private readonly SeerrUserMap _seerrUsers;
    private readonly UserRef _mario;
    private readonly UserRef _admin;
    private readonly UserRef _approver;

    public NotificationsControllerTests()
    {
        _push = new PushService(
            new NotificationStore(_folder.NotificationsFile, NullLogger<NotificationStore>.Instance),
            new VapidKeyProvider(() => null, () => { }),
            _transport, _devices, _server, TimeProvider.System, NullLogger<PushService>.Instance);
        _seerrUsers = new SeerrUserMap(_seerr, TimeProvider.System, NullLogger<SeerrUserMap>.Instance);
        _mario = _server.AddUser("Mario");
        _admin = _server.AddUser("Admin", isAdmin: true);
        _approver = _server.AddUser("Approvatore");
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = SeerrPermissions.ManageRequests, JellyfinUserId = _approver.Id.ToString("N") });
    }

    public void Dispose() => _folder.Dispose();

    private NotificationsController Controller(UserRef user, string deviceId = "d")
    {
        var auth = new AuthorizationInfo
        {
            DeviceId = deviceId, Client = "WonderFlix", User = new User(user.Name, "provider", "reset") { Id = user.Id }, IsAuthenticated = true,
        };
        return new NotificationsController(new FakeAuthorizationContext(auth), _push, _server, _seerrUsers)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status(ActionResult result) => ((IStatusCodeActionResult)result).StatusCode!.Value;

    private async Task<IReadOnlyList<string>> TypesOf(UserRef user) =>
        (await Controller(user).Get(CancellationToken.None)).Value!.Types.Select(t => t.Type).ToList();

    private static SubscribeRequest Subscription(string name = "a") => new()
    {
        Endpoint = $"https://fcm.googleapis.com/fcm/send/{name}",
        P256dh = Base64Url.Encode(NewPoint()),
        Auth = Base64Url.Encode(RandomNumberGenerator.GetBytes(16)),
        Language = "it",
    };

    private static byte[] NewPoint()
    {
        using var key = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var q = key.ExportParameters(false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }

    private Task Announce(UserRef user) =>
        _push.DeliverAsync([(user.Id, new InboxEntry { Id = "voce-1", Type = InboxEntryTypes.Announcement, Text = "Ciao" })]);

    [Fact]
    public async Task Get_UserSeesEveryoneTypesOnly()
    {
        var types = await TypesOf(_mario);
        Assert.Contains(InboxEntryTypes.Invite, types);
        Assert.DoesNotContain(InboxEntryTypes.RequestPending, types);
        Assert.DoesNotContain(InboxEntryTypes.ReportPending, types);
    }

    [Fact]
    public async Task Get_AdminSeesAdminTypes()
    {
        var types = await TypesOf(_admin);
        Assert.Contains(InboxEntryTypes.ReportPending, types);
        Assert.Contains(InboxEntryTypes.DiskAlmostFull, types);
        Assert.DoesNotContain(InboxEntryTypes.RequestPending, types);
    }

    [Fact]
    public async Task Get_ApproverSeesRequestPending()
    {
        var types = await TypesOf(_approver);
        Assert.Contains(InboxEntryTypes.RequestPending, types);
        Assert.DoesNotContain(InboxEntryTypes.ReportPending, types);
    }

    [Fact]
    public async Task Get_SeerrDown_IsNotApproverButStillAnswers()
    {
        _seerr.FailWith = SeerrError.Unavailable;
        var types = await TypesOf(_approver);
        Assert.Contains(InboxEntryTypes.Invite, types);
        Assert.DoesNotContain(InboxEntryTypes.RequestPending, types);
    }

    [Fact]
    public async Task Get_ReturnsVapidPublicKey()
    {
        var response = (await Controller(_mario).Get(CancellationToken.None)).Value!;
        Assert.True(Base64Url.TryDecode(response.VapidPublicKey, out var key));
        Assert.Equal(65, key.Length);
    }

    [Fact]
    public async Task Put_TogglesAType()
    {
        Assert.Equal(204, Status(await Controller(_mario).SetType(InboxEntryTypes.Announcement, new NotificationTypeRequest { Enabled = false }, CancellationToken.None)));
        var announcement = (await Controller(_mario).Get(CancellationToken.None)).Value!.Types.Single(t => t.Type == InboxEntryTypes.Announcement);
        Assert.False(announcement.Enabled);
    }

    [Fact]
    public async Task Put_UnknownOrHiddenType_400()
    {
        var body = new NotificationTypeRequest { Enabled = false };
        Assert.Equal(400, Status(await Controller(_mario).SetType("Nope", body, CancellationToken.None)));
        Assert.Equal(400, Status(await Controller(_mario).SetType(InboxEntryTypes.ReportPending, body, CancellationToken.None)));
        Assert.Equal(400, Status(await Controller(_mario).SetType(InboxEntryTypes.Announcement, null, CancellationToken.None)));
    }

    [Fact]
    public async Task Subscribe_StoresDeviceIdFromAuth()
    {
        Assert.Equal(204, Status(await Controller(_mario, "dev-1").Subscribe(Subscription())));

        // Solo il dispositivo dell'autenticazione ha accesso: la push parte solo se è quello salvato.
        _devices.Allow(_mario.Id, "dev-1");
        await Announce(_mario);
        Assert.Single(_transport.Sent);
    }

    [Fact]
    public async Task Subscribe_NonHttpsEndpoint_400()
    {
        var request = Subscription();
        request.Endpoint = "http://fcm.googleapis.com/fcm/send/a";
        Assert.Equal(400, Status(await Controller(_mario).Subscribe(request)));
        Assert.Equal(400, Status(await Controller(_mario).Subscribe(null)));
    }

    [Fact]
    public async Task Subscribe_BadKeys_400()
    {
        var request = Subscription();
        request.P256dh = "non base64url!";
        Assert.Equal(400, Status(await Controller(_mario).Subscribe(request)));

        request = Subscription();
        request.Auth = Base64Url.Encode(new byte[3]);
        Assert.Equal(400, Status(await Controller(_mario).Subscribe(request)));
    }

    [Fact]
    public async Task Unsubscribe_OnlyCallers()
    {
        var request = Subscription();
        await Controller(_mario, "dev-m").Subscribe(request);
        _devices.Allow(_mario.Id, "dev-m");

        // Un altro utente non toglie l'iscrizione di Mario.
        Assert.Equal(204, Status(await Controller(_admin).Unsubscribe(new UnsubscribeRequest { Endpoint = request.Endpoint })));
        await Announce(_mario);
        Assert.Single(_transport.Sent);

        Assert.Equal(204, Status(await Controller(_mario).Unsubscribe(new UnsubscribeRequest { Endpoint = request.Endpoint })));
        await Announce(_mario);
        Assert.Single(_transport.Sent);
    }
}
