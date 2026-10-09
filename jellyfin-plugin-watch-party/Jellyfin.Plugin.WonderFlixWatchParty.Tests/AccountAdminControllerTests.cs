using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
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

    private AccountAdminController Controller(AccountAdmin? admin = null, PasswordRecovery? recovery = null)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _peach, IsAuthenticated = true };
        return new AccountAdminController(new FakeAuthorizationContext(auth), admin ?? _rig.Admin(), recovery ?? _rig.Recovery())
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
        Assert.Equal(204, ActionResults.Status(await controller.Unlink(mario.Id.ToString())));
        ActionResults.AssertError(409, "NoContacts", (await controller.SendRecovery(mario.Id.ToString(), null)).Result);
        ActionResults.AssertError(400, "UnknownUser", await controller.Unlink("non-un-id"));
    }

    // Chi ha mandato il codice o scollegato i contatti finisce nel registro del server: è l'admin che chiama.
    [Fact]
    public async Task TheLogHasTheAdminWhoCalled()
    {
        var mario = _rig.UserWithContacts("Mario");
        var adminLogger = new RecordingLogger<AccountAdmin>();
        var recoveryLogger = new RecordingLogger<PasswordRecovery>();
        var controller = Controller(
            new AccountAdmin(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Sender, _rig.Discord, _rig.Settings, adminLogger),
            new PasswordRecovery(_rig.Server, _rig.Contacts, _rig.Codes, _rig.Limiter, _rig.Sender, _rig.Passwords, recoveryLogger));

        await controller.SendRecovery(mario.Id.ToString("N"), null);
        await controller.Unlink(mario.Id.ToString("N"));

        Assert.Contains($"dall'admin {_peach.Id:N}", Assert.Single(recoveryLogger.Entries).Message, StringComparison.Ordinal);
        Assert.Contains($"dall'admin {_peach.Id:N}", Assert.Single(adminLogger.Entries).Message, StringComparison.Ordinal);
    }
}
