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
/// Il match del film (spec P §6.4), con la stessa policy degli amici. Chi
/// chiama è l'utente dell'autenticazione. Mai 404: roomId senza vincoli di
/// rotta, un id non valido è 400; i 409 hanno {Reason}.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class MatchController(
    IAuthorizationContext authorizationContext,
    MatchService matches) : ControllerBase
{
    /// <summary>Apre una sala; 409 InAnotherRoom se chi chiama è già in una.</summary>
    [HttpPost("Match")]
    public async Task<ActionResult<MatchStateDto>> Open() =>
        Result(matches.Open(await CallerAsync().ConfigureAwait(false)));

    /// <summary>Lo stato della sala, per i membri.</summary>
    [HttpGet("Match/{roomId}")]
    public async Task<ActionResult<MatchStateDto>> Get([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.Get(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Invita amici, in attesa (solo chi ha aperto).</summary>
    [HttpPost("Match/{roomId}/Invites")]
    public async Task<ActionResult> Invite([FromRoute] string roomId, [FromBody] InviteRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id))
        {
            return BadRequest();
        }

        var caller = await CallerAsync().ConfigureAwait(false);
        return Result(await matches.InviteAsync(caller, id, request?.UserIds).ConfigureAwait(false));
    }

    /// <summary>Entra un invitato.</summary>
    [HttpPost("Match/{roomId}/Join")]
    public async Task<ActionResult<MatchStateDto>> Join([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.Join(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Esce chi chiama; 204 anche se non era nella sala.</summary>
    [HttpPost("Match/{roomId}/Leave")]
    public async Task<ActionResult> Leave([FromRoute] string roomId)
    {
        if (!Guid.TryParse(roomId, out var id))
        {
            return BadRequest();
        }

        matches.Leave(await CallerAsync().ConfigureAwait(false), id);
        return NoContent();
    }

    /// <summary>"Inizia" con i filtri; 400 con un filtro sconosciuto.</summary>
    [HttpPost("Match/{roomId}/Start")]
    public async Task<ActionResult<MatchStateDto>> Start([FromRoute] string roomId, [FromBody] MatchStartRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id)
            || MatchFilters.Parse(request?.Type, request?.Duration, request?.Genre) is not { } filters)
        {
            return BadRequest();
        }

        return Result(matches.Start(await CallerAsync().ConfigureAwait(false), id, filters));
    }

    /// <summary>Il voto per il prossimo titolo; 400 senza ItemId valido o senza Yes.</summary>
    [HttpPost("Match/{roomId}/Votes")]
    public async Task<ActionResult> Vote([FromRoute] string roomId, [FromBody] MatchVoteRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id)
            || !Guid.TryParse(request?.ItemId, out var itemId)
            || request?.Yes is not { } yes)
        {
            return BadRequest();
        }

        return Result(matches.Vote(await CallerAsync().ConfigureAwait(false), id, itemId, yes));
    }

    /// <summary>"Altri 30", quando tutti hanno finito (solo chi ha aperto).</summary>
    [HttpPost("Match/{roomId}/More")]
    public async Task<ActionResult<MatchStateDto>> More([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.More(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Il party avviato da chi ha aperto: i membri ci entrano, la sala si chiude.</summary>
    [HttpPost("Match/{roomId}/Party")]
    public async Task<ActionResult> Party([FromRoute] string roomId, [FromBody] MatchPartyRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id) || !Guid.TryParse(request?.GroupId, out var groupId))
        {
            return BadRequest();
        }

        return Result(matches.Party(await CallerAsync().ConfigureAwait(false), id, groupId));
    }

    private static ActionResult Result(MatchOutcome outcome) => outcome.Status switch
    {
        HubStatus.Ok when outcome.State is { } state => new OkObjectResult(state),
        HubStatus.Ok => new NoContentResult(),
        HubStatus.Conflict => new ObjectResult(new MatchErrorDto(outcome.Reason ?? MatchReasons.Closed))
        {
            StatusCode = StatusCodes.Status409Conflict,
        },
        HubStatus.RateLimited => new StatusCodeResult(StatusCodes.Status429TooManyRequests),
        _ => new BadRequestResult(),
    };

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
