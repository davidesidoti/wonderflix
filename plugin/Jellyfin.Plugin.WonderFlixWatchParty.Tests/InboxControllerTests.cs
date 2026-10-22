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

public sealed class InboxControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly InboxService _inbox;
    private readonly NewTitlesCollector _newTitles;

    public InboxControllerTests()
    {
        // Senza accesso ai watch party: la cassetta vale lo stesso.
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, false);
        _inbox = TestInbox.Create(_server, _folder, _time);
        _newTitles = TestNewTitles.Create(_server, _inbox, _time);
    }

    public void Dispose()
    {
        _newTitles.Dispose();
        _folder.Dispose();
    }

    private InboxController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new InboxController(new FakeAuthorizationContext(auth), _inbox, _newTitles, _server)
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

    [Fact]
    public async Task ReadRemoveAndClearAnswer204()
    {
        await _inbox.AnnounceAsync("uno");
        await _inbox.AnnounceAsync("due");
        var controller = Controller(_mario);
        var inbox = (await controller.GetInbox()).Value!;
        Assert.Equal(2, inbox.Unread);

        Assert.Equal(204, Status(await controller.MarkRead(new InboxReadRequest { UpTo = inbox.Entries[0].Seq })));
        Assert.Equal(0, (await controller.GetInbox()).Value!.Unread);
        Assert.Equal(204, Status(await controller.RemoveEntry(inbox.Entries[0].Id)));
        // Una voce che non c'è (o un id che non è un Guid): 204 lo stesso, mai 404.
        Assert.Equal(204, Status(await controller.RemoveEntry("non-esiste")));
        Assert.Single((await controller.GetInbox()).Value!.Entries);
        Assert.Equal(204, Status(await controller.Clear()));
        Assert.Empty((await controller.GetInbox()).Value!.Entries);
        Assert.Equal(400, Status(await controller.MarkRead(null)));
    }

    [Fact]
    public async Task AnnouncementsAnswerTheRecipientsOr400()
    {
        var controller = Controller(_mario);
        Assert.Equal(1, (await controller.Announce(new AnnouncementRequest { Text = "ciao" })).Value!.Recipients);
        Assert.Equal(400, Status((await controller.Announce(new AnnouncementRequest { Text = " " })).Result!));
        Assert.Equal(400, Status((await controller.Announce(null)).Result!));
    }

    [Fact]
    public void EveryUserReadsTheInboxOnlyAdminsAnnounce()
    {
        var authorize = Assert.Single(typeof(InboxController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        var announce = Assert.Single(typeof(InboxController).GetMethod(nameof(InboxController.Announce))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, announce.Policy);
    }

    [Fact]
    public async Task NewTitlesStatusAndSendNow()
    {
        var controller = Controller(_mario);
        Assert.Equal(new NewTitlesStatus(true, 0), controller.GetNewTitles().Value);

        var dune = Guid.NewGuid();
        _server.Titles[dune] = new LibraryTitle(
            dune, true, "Dune", 2024, Guid.Empty, string.Empty, string.Empty, null, null, [], true);
        _newTitles.Added(dune);
        Assert.Equal(new NewTitlesStatus(true, 1), controller.GetNewTitles().Value);
        Assert.Equal(new NewTitlesSendResponse(1, 1), (await controller.SendNewTitles()).Value);
        Assert.Equal(new NewTitlesStatus(true, 0), controller.GetNewTitles().Value);

        _server.NotifyNewTitles = false;
        Assert.Equal(new NewTitlesStatus(false, 0), controller.GetNewTitles().Value);
    }

    [Fact]
    public void OnlyAdminsSeeAndSendNewTitles()
    {
        foreach (var name in new[] { nameof(InboxController.GetNewTitles), nameof(InboxController.SendNewTitles) })
        {
            var authorize = Assert.Single(typeof(InboxController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>());
            Assert.Equal(Policies.RequiresElevation, authorize.Policy);
        }
    }
}
