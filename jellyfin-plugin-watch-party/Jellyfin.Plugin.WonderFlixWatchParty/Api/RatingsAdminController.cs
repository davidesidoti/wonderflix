using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I commenti dei voti, per gli admin (spec Q §6.4). Controller a parte: la
/// policy degli amici della classe si sommerebbe a quella del metodo, e un
/// admin senza SyncPlay (o la chiave API) resterebbe fuori. Come gli annunci
/// di InboxController, la classe ha [Authorize] e i metodi RequiresElevation.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class RatingsAdminController(
    IAuthorizationContext authorizationContext,
    RatingService ratings) : ControllerBase
{
    /// <summary>I commenti dal più recente, 50 per pagina; before è l'UpdatedAt di Next.</summary>
    [HttpGet("Ratings/Admin/Comments")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<AdminCommentsDto> GetComments([FromQuery] string? before)
    {
        var result = ratings.Comments(before);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    /// <summary>Toglie il commento, non il voto; 204 anche se non c'era.</summary>
    [HttpDelete("Ratings/Admin/Comments/{userId}/{itemId}")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult> DeleteComment([FromRoute] string userId, [FromRoute] string itemId)
    {
        var admin = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        return RatingsController.Status(ratings.DeleteComment(admin, userId, itemId));
    }
}
