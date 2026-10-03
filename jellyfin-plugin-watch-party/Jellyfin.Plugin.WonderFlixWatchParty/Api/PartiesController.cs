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
/// Endpoint dei party (spec F §6.7). Serve la sessione di chi chiama (i
/// gruppi SyncPlay si vedono da una sessione): senza, 409 come il canale.
/// Mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class PartiesController(
    IAuthorizationContext authorizationContext,
    ISessionDirectory sessions,
    PartyService parties,
    PresenceTracker presence) : ControllerBase
{
    /// <summary>Registra il party appena creato con la sua modalità.</summary>
    [HttpPost("Parties/{groupId:guid}")]
    public async Task<ActionResult<RegisterPartyResponse>> Register(
        [FromRoute] Guid groupId,
        [FromBody] RegisterPartyRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = parties.Register(caller, groupId, request?.Mode);
        if (result.Status != HubStatus.Ok)
        {
            return Failure(result.Status);
        }

        // L'ingresso nel canale è avvenuto prima della registrazione, quando
        // il party non era ancora visibile: gli amici lo rileggono adesso.
        presence.Changed(caller.UserId);
        return result.Value!;
    }

    /// <summary>I party che chi chiama può vedere.</summary>
    [HttpGet("Parties")]
    public async Task<ActionResult<IReadOnlyList<PartySummary>>> List()
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        return caller is null ? Conflict() : Ok(parties.ListVisible(caller));
    }

    /// <summary>Modalità e codice, per chi è nel gruppo.</summary>
    [HttpGet("Parties/{groupId:guid}")]
    public async Task<ActionResult<PartyDetails>> Details([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = parties.GetDetails(caller, groupId);
        return result.Status == HubStatus.Ok ? result.Value! : Failure(result.Status);
    }

    /// <summary>Il gruppo di un codice.</summary>
    [HttpPost("Parties/Join")]
    public async Task<ActionResult<JoinByCodeResponse>> JoinByCode([FromBody] JoinByCodeRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = parties.JoinByCode(caller, request?.Code);
        return result.Status == HubStatus.Ok ? result.Value! : Failure(result.Status);
    }

    /// <summary>Invita amici di chi chiama.</summary>
    [HttpPost("Parties/{groupId:guid}/Invites")]
    public async Task<ActionResult> Invite([FromRoute] Guid groupId, [FromBody] InviteRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var status = await parties.InviteAsync(caller, groupId, request?.UserIds).ConfigureAwait(false);
        return status == HubStatus.Ok ? NoContent() : Failure(status);
    }

    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
        HubStatus.Conflict => Conflict(),
        HubStatus.RateLimited => StatusCode(StatusCodes.Status429TooManyRequests),
        _ => BadRequest(),
    };

    private async Task<CallerSession?> FindCallerAsync()
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        return sessions.FindCaller(auth.DeviceId, auth.Client, auth.UserId);
    }
}
