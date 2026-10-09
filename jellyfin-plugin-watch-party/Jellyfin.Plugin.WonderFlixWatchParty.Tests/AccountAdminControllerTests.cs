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
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountAdminControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly User _peach = new("peach", "provider", "reset");

    public AccountAdminControllerTests() =>
        _rig.Server.Users[_peach.Id] = new UserRef(_peach.Id, "peach", true, true, IsAdmin: true);

    public void Dispose() => _rig.Dispose();

    private AccountAdminController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _peach, IsAuthenticated = true };
        return new AccountAdminController(new FakeAuthorizationContext(auth), _rig.Admin(), _rig.Recovery())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public void OnlyForAdmins()
    {
        var authorize = Assert.Single(typeof(AccountAdminController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, authorize.Policy);
        Assert.Equal(
            "WonderFlixWatchParty/Account/Admin",
            typeof(AccountAdminController).GetCustomAttribute<RouteAttribute>()!.Template);
    }

    [Fact]
    public async Task UsersStatusAndTest()
    {
        _rig.UserWithContacts("Mario");
        var controller = Controller();

        Assert.Equal(new[] { "Mario", "peach" }, controller.GetUsers().Value!.Select(u => u.Name));
        Assert.Equal(1, controller.Status().Value!.WithContacts);
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), (await controller.Test(new AccountTestRequest { Language = "it" })).Value);
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), (await controller.Test(null)).Value);
    }

    [Fact]
    public async Task RecoveryAndUnlinkByUserId()
    {
        var mario = _rig.UserWithContacts("Mario");
        var controller = Controller();

        Assert.Equal(
            new[] { "Discord", "Email" },
            (await controller.SendRecovery(mario.Id.ToString("N"), new AccountLanguageRequest { Language = "it" })).Value!.Channels);
        ActionResults.AssertError(403, "NotAllowed", (await controller.SendRecovery(_peach.Id.ToString(), null)).Result);
        ActionResults.AssertError(400, "UnknownUser", (await controller.SendRecovery("non-un-id", null)).Result);
        ActionResults.AssertError(400, "UnknownUser", (await controller.SendRecovery(Guid.NewGuid().ToString(), null)).Result);
        Assert.Equal(204, ActionResults.Status(controller.Unlink(mario.Id.ToString())));
        ActionResults.AssertError(409, "NoContacts", (await controller.SendRecovery(mario.Id.ToString(), null)).Result);
        ActionResults.AssertError(400, "UnknownUser", controller.Unlink("non-un-id"));
    }
}
