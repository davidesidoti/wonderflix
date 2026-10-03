using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Endpoint del plugin (spec E §6.2). Non risponde mai 404: per l'app un 404
/// vuol dire che la rotta non esiste, cioè plugin assente. Ingresso e uscita
/// cambiano la presenza: gli amici vedono "Nel watch party" (spec F §6.3).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class WatchPartyController(
    IAuthorizationContext authorizationContext,
    ISessionDirectory sessions,
    PartyHub hub,
    PresenceTracker presence) : ControllerBase
{
    /// <summary>Registra la sessione nel gruppo; restituisce lo storico della chat.</summary>
    [HttpPost("Groups/{groupId:guid}/Join")]
    public async Task<ActionResult<JoinResponse>> Join([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = hub.Join(caller, groupId);
        if (result.Status != HubStatus.Ok)
        {
            return Failure(result.Status);
        }

        presence.Changed(caller.UserId);
        return new JoinResponse(result.Value!);
    }

    /// <summary>Toglie la sessione dal gruppo.</summary>
    [HttpPost("Groups/{groupId:guid}/Leave")]
    public async Task<ActionResult> Leave([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is not null)
        {
            hub.Leave(caller, groupId);
            presence.Changed(caller.UserId);
        }

        return NoContent();
    }

    /// <summary>Un annuncio, un messaggio o una reazione: lo timbra e lo inoltra.</summary>
    [HttpPost("Groups/{groupId:guid}/Events")]
    public async Task<ActionResult<StampedEvent>> PostEvent(
        [FromRoute] Guid groupId,
        [FromBody] EventRequest? request,
        CancellationToken cancellationToken)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = await hub.PostAsync(caller, groupId, request, cancellationToken).ConfigureAwait(false);
        if (result.Status != HubStatus.Ok)
        {
            return Failure(result.Status);
        }

        return result.Value!;
    }

    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
        HubStatus.RateLimited => StatusCode(StatusCodes.Status429TooManyRequests),
        _ => BadRequest(),
    };

    private async Task<CallerSession?> FindCallerAsync()
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        return sessions.FindCaller(auth.DeviceId, auth.Client, auth.UserId);
    }
}
