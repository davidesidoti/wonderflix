using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly User _mario = new("mario", "provider", "reset");

    public AccountControllerTests()
    {
        _rig.Server.Users[_mario.Id] = new UserRef(_mario.Id, "mario", true, true);
        _rig.Discord.Members["mario"] = new DiscordMember("222222222222222222", "mario");
    }

    public void Dispose() => _rig.Dispose();

    private AccountController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new AccountController(new FakeAuthorizationContext(auth), _rig.Linking())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task StartAnswers202ThenConfirmGivesTheContacts()
    {
        var controller = Controller();

        var start = (await controller.Start("discord", new LinkStartRequest { Target = "mario", Language = "it" })).Result!;

        Assert.Equal(202, ActionResults.Status(start));
        Assert.IsType<LinkStartResponse>(Assert.IsType<ObjectResult>(start).Value);
        var confirm = await controller.Confirm("Discord", new LinkConfirmRequest { Code = _rig.Discord.LastCode("222222222222222222") });
        Assert.Equal("mario", confirm.Value!.Discord!.Name);
        Assert.Equal("mario", (await controller.GetContacts()).Value!.Discord!.Name);
        Assert.Equal(204, ActionResults.Status(await controller.Unlink("DISCORD")));
        Assert.Null((await controller.GetContacts()).Value!.Discord);
    }

    [Fact]
    public async Task ErrorsHaveAStatusAndACode()
    {
        var controller = Controller();

        ActionResults.AssertError(400, "Invalid", (await controller.Start("Telegram", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "Invalid", (await controller.Start("Discord", null)).Result);
        ActionResults.AssertError(400, "InvalidTarget", (await controller.Start("Email", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "MemberNotFound", (await controller.Start("Discord", new LinkStartRequest { Target = "luigi" })).Result);
        // Il nome sbagliato non ha usato il minuto: il codice mandato sì.
        Assert.Equal(202, ActionResults.Status((await controller.Start("Discord", new LinkStartRequest { Target = "mario" })).Result!));
        ActionResults.AssertError(429, "RateLimited", (await controller.Start("Discord", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "InvalidCode", (await controller.Confirm("Discord", new LinkConfirmRequest { Code = "000000" })).Result);
        ActionResults.AssertError(400, "Invalid", (await controller.Confirm("Discord", null)).Result);
        ActionResults.AssertError(400, "Invalid", await controller.Unlink("0"));
        _rig.Settings.SmtpHost = string.Empty;
        ActionResults.AssertError(503, "ChannelOff", (await controller.Start("Email", new LinkStartRequest { Target = "mario@example.com" })).Result);
    }

    [Fact]
    public async Task SendErrorsAre409And502()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        ActionResults.AssertError(409, "DmClosed", (await Controller().Start("Discord", new LinkStartRequest { Target = "mario" })).Result);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        ActionResults.AssertError(502, "SendFailed", (await Controller().Start("Email", new LinkStartRequest { Target = "mario@example.com" })).Result);
    }

    [Theory]
    [InlineData(AccountError.ChannelOff, 503)]
    [InlineData(AccountError.RateLimited, 429)]
    [InlineData(AccountError.InvalidTarget, 400)]
    [InlineData(AccountError.MemberNotFound, 400)]
    [InlineData(AccountError.DmClosed, 409)]
    [InlineData(AccountError.SendFailed, 502)]
    [InlineData(AccountError.InvalidCode, 400)]
    [InlineData(AccountError.WeakPassword, 400)]
    [InlineData(AccountError.NotAllowed, 403)]
    [InlineData(AccountError.NoContacts, 409)]
    [InlineData(AccountError.UnknownUser, 400)]
    [InlineData(AccountError.Invalid, 400)]
    public void EveryErrorHasItsStatusAndNever404(AccountError error, int status)
    {
        var result = AccountErrors.Result(error);

        Assert.Equal(status, result.StatusCode);
        Assert.Equal(error.ToString(), Assert.IsType<AccountErrorDto>(result.Value).Code);
    }

    [Fact]
    public void ContactsAreForEveryAuthenticatedUser()
    {
        var authorize = Assert.Single(typeof(AccountController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Equal("WonderFlixWatchParty/Account", typeof(AccountController).GetCustomAttribute<RouteAttribute>()!.Template);
    }
}
