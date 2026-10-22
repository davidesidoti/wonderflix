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
/// I voti degli amici (spec Q §6.3): votazione di fine party e scheda del
/// titolo, con la stessa policy degli amici. Chi chiama è l'utente
/// dell'autenticazione. Mai 404: gli id sono stringhe senza vincoli di
/// rotta, un id non valido è 400; i 409 hanno {Reason}.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class RatingsController(
    IAuthorizationContext authorizationContext,
    RatingService ratings,
    RatingRoundService rounds) : ControllerBase
{
    /// <summary>Apre la votazione di un titolo per il gruppo (idempotente sul titolo).</summary>
    [HttpPost("Ratings/Rounds")]
    public async Task<ActionResult<RatingRoundDto>> OpenRound([FromBody] OpenRatingRoundRequest? request) =>
        Result(rounds.Open(await CallerAsync().ConfigureAwait(false), request));

    /// <summary>Lo stato della votazione; {} se non ce n'è.</summary>
    [HttpGet("Ratings/Rounds/{groupId}")]
    public async Task<ActionResult<RatingRoundDto>> GetRound([FromRoute] string groupId) =>
        Guid.TryParse(groupId, out var id)
            ? Result(rounds.Get(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Il voto di chi chiama nella votazione.</summary>
    [HttpPost("Ratings/Rounds/{groupId}/Vote")]
    public async Task<ActionResult<RatingRoundDto>> VoteInRound([FromRoute] string groupId, [FromBody] RateRequest? request) =>
        Guid.TryParse(groupId, out var id)
            ? Result(rounds.Vote(await CallerAsync().ConfigureAwait(false), id, request))
            : BadRequest();

    /// <summary>"Non voto".</summary>
    [HttpPost("Ratings/Rounds/{groupId}/Skip")]
    public async Task<ActionResult<RatingRoundDto>> SkipRound([FromRoute] string groupId) =>
        Guid.TryParse(groupId, out var id)
            ? Result(rounds.Skip(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Scopre i voti (solo il creatore).</summary>
    [HttpPost("Ratings/Rounds/{groupId}/Reveal")]
    public async Task<ActionResult<RatingRoundDto>> RevealRound([FromRoute] string groupId) =>
        Guid.TryParse(groupId, out var id)
            ? Result(rounds.Reveal(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>La scheda di un titolo: il voto di chi chiama, la media e gli amici.</summary>
    [HttpGet("Ratings")]
    public async Task<ActionResult<ItemRatingsDto>> GetRatings([FromQuery] string? itemId)
    {
        var result = ratings.ForItem(await CallerAsync().ConfigureAwait(false), itemId);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    /// <summary>Mette o cambia il voto dalla scheda.</summary>
    [HttpPut("Ratings/{itemId}")]
    public async Task<ActionResult> Rate([FromRoute] string itemId, [FromBody] RateRequest? request) =>
        Status(ratings.Rate(await CallerAsync().ConfigureAwait(false), itemId, request));

    /// <summary>Toglie il voto.</summary>
    [HttpDelete("Ratings/{itemId}")]
    public async Task<ActionResult> DeleteRating([FromRoute] string itemId) =>
        Status(ratings.Delete(await CallerAsync().ConfigureAwait(false), itemId));

    internal static ActionResult Status(HubStatus status) => status switch
    {
        HubStatus.Ok => new NoContentResult(),
        HubStatus.RateLimited => new StatusCodeResult(StatusCodes.Status429TooManyRequests),
        _ => new BadRequestResult(),
    };

    private static ActionResult Result(RatingOutcome outcome) => outcome.Status switch
    {
        HubStatus.Ok => new OkObjectResult((object?)outcome.State ?? new RatingRoundEmptyDto()),
        HubStatus.Conflict => new ObjectResult(new RatingErrorDto(outcome.Reason ?? RatingReasons.Closed))
        {
            StatusCode = StatusCodes.Status409Conflict,
        },
        HubStatus.RateLimited => new StatusCodeResult(StatusCodes.Status429TooManyRequests),
        _ => new BadRequestResult(),
    };

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
