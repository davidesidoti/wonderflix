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
/// I consigli tra amici (spec N §6.2), con la stessa policy degli amici.
/// Chi chiama è l'utente dell'autenticazione. Come il resto del plugin,
/// mai 404: gli id sono stringhe senza vincoli di rotta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class RecommendationsController(
    IAuthorizationContext authorizationContext,
    RecommendationService recommendations) : ControllerBase
{
    /// <summary>Gli amici a cui si può consigliare il titolo, con online e accesso.</summary>
    [HttpGet("Recommendations/Targets")]
    public async Task<ActionResult<RecommendationTargetsResponse>> GetTargets([FromQuery] string? itemId)
    {
        var result = recommendations.Targets(await CallerAsync().ConfigureAwait(false), itemId);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    /// <summary>Consiglia il titolo agli amici scelti; risponde a quanti è arrivato.</summary>
    [HttpPost("Recommendations")]
    public async Task<ActionResult<RecommendResponse>> Recommend([FromBody] RecommendRequest? request)
    {
        var result = await recommendations.RecommendAsync(await CallerAsync().ConfigureAwait(false), request).ConfigureAwait(false);
        if (result.Status == HubStatus.Ok)
        {
            return result.Value!;
        }

        return result.Status == HubStatus.RateLimited ? StatusCode(StatusCodes.Status429TooManyRequests) : BadRequest();
    }

    /// <summary>I consigli ricevuti ancora validi, dal più recente.</summary>
    [HttpGet("Recommendations")]
    public async Task<ActionResult<RecommendationsResponse>> GetRecommendations() =>
        recommendations.List(await CallerAsync().ConfigureAwait(false));

    /// <summary>"Non mi interessa"; 204 anche se il titolo non c'è.</summary>
    [HttpDelete("Recommendations/{itemId}")]
    public async Task<ActionResult> Dismiss([FromRoute] string itemId)
    {
        recommendations.Dismiss(await CallerAsync().ConfigureAwait(false), itemId);
        return NoContent();
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
