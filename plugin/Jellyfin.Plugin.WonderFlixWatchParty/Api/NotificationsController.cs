using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le notifiche push dell'utente (spec V): quali riceve e i suoi dispositivi iscritti. Chi chiama è l'utente
/// dell'autenticazione, il dispositivo quello della sua sessione. Come il resto del plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class NotificationsController(
    IAuthorizationContext authorizationContext,
    PushService push,
    IUserDirectory users,
    SeerrUserMap seerrUsers) : ControllerBase
{
    /// <summary>La chiave VAPID e i tipi che chi chiama può ricevere, con il suo interruttore.</summary>
    [HttpGet("Notifications")]
    public async Task<ActionResult<NotificationsResponse>> Get(CancellationToken cancellationToken)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        var (isAdmin, isApprover) = await RolesAsync(auth.UserId, cancellationToken).ConfigureAwait(false);
        return push.Get(auth.UserId, isAdmin, isApprover);
    }

    /// <summary>Accende o spegne un tipo; 400 se non esiste o chi chiama non lo vede.</summary>
    [HttpPut("Notifications/Types/{type}")]
    public async Task<ActionResult> SetType(
        [FromRoute] string type, [FromBody] NotificationTypeRequest? request, CancellationToken cancellationToken)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        if (request is null)
        {
            return BadRequest();
        }

        var (isAdmin, isApprover) = await RolesAsync(auth.UserId, cancellationToken).ConfigureAwait(false);
        return push.SetEnabled(auth.UserId, type, request.Enabled, isAdmin, isApprover) ? NoContent() : BadRequest();
    }

    /// <summary>Iscrive il dispositivo di chi chiama; 400 se endpoint o chiavi non sono validi.</summary>
    [HttpPost("Notifications/Subscriptions")]
    public async Task<ActionResult> Subscribe([FromBody] SubscribeRequest? request)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        return push.Subscribe(auth.UserId, auth.DeviceId, request) == HubStatus.Ok ? NoContent() : BadRequest();
    }

    /// <summary>Toglie l'iscrizione di chi chiama; se non c'è, 204 lo stesso.</summary>
    [HttpDelete("Notifications/Subscriptions")]
    public async Task<ActionResult> Unsubscribe([FromBody] UnsubscribeRequest? request)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        push.Unsubscribe(auth.UserId, request?.Endpoint ?? string.Empty);
        return NoContent();
    }

    // Seerr non configurato o non raggiungibile: chi chiama non approva, la richiesta non fallisce.
    private async Task<(bool IsAdmin, bool IsApprover)> RolesAsync(Guid userId, CancellationToken cancellationToken)
    {
        var isAdmin = users.GetUser(userId)?.IsAdmin == true;
        try
        {
            var managers = await seerrUsers.ManagerJellyfinIdsAsync(cancellationToken).ConfigureAwait(false);
            return (isAdmin, managers.Contains(userId));
        }
        catch (SeerrException)
        {
            return (isAdmin, false);
        }
    }
}
