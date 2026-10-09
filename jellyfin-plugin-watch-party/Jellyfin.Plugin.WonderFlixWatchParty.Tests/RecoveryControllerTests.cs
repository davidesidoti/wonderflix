using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecoveryControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly UserRef _mario;
    private readonly RecoveryController _controller;

    public RecoveryControllerTests()
    {
        _mario = _rig.UserWithContacts("Mario");
        _controller = new RecoveryController(_rig.Recovery())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    public void Dispose() => _rig.Dispose();

    [Fact]
    public void RecoveryNeedsNoAccess()
    {
        Assert.NotNull(typeof(RecoveryController).GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.Empty(typeof(RecoveryController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            "WonderFlixWatchParty/Account/Recovery",
            typeof(RecoveryController).GetCustomAttribute<RouteAttribute>()!.Template);
    }

    [Fact]
    public void StartAnswers202ThenTooMany()
    {
        Assert.Equal(202, ActionResults.Status(_controller.Start(new RecoveryStartRequest { Username = "nessuno", Language = "it" })));
        ActionResults.AssertError(429, "RateLimited", _controller.Start(new RecoveryStartRequest { Username = "nessuno" }));
        ActionResults.AssertError(400, "Invalid", _controller.Start(null));
        ActionResults.AssertError(400, "Invalid", _controller.Start(new RecoveryStartRequest { Username = " " }));
    }

    [Fact]
    public async Task CompleteAnswers204OrTheError()
    {
        ActionResults.AssertError(400, "Invalid", await _controller.Complete(null));
        ActionResults.AssertError(
            400, "WeakPassword",
            await _controller.Complete(new RecoveryCompleteRequest { Username = "mario", Code = "000000", NewPassword = "123" }));
        ActionResults.AssertError(
            400, "InvalidCode",
            await _controller.Complete(new RecoveryCompleteRequest { Username = "mario", Code = "000000", NewPassword = "nuova-password" }));
        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);

        var done = await _controller.Complete(new RecoveryCompleteRequest
        {
            Username = "mario",
            Code = code,
            NewPassword = "nuova-password",
            Language = "it",
        });

        Assert.Equal(204, ActionResults.Status(done));
        Assert.Equal(new[] { (_mario.Id, "nuova-password") }, _rig.Passwords.Calls);
    }
}
