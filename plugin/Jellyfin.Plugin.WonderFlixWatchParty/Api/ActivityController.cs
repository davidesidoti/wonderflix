using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Cosa guardano gli amici (spec O §6.1, §6.6), con la stessa policy degli
/// amici. Chi chiama è l'utente dell'autenticazione.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class ActivityController(
    IAuthorizationContext authorizationContext,
    ActivityService activity) : ControllerBase
{
    /// <summary>"Mostra agli amici cosa guardo" di chi chiama.</summary>
    [HttpGet("Activity/Settings")]
    public async Task<ActionResult<ActivitySettingsResponse>> GetSettings() =>
        new ActivitySettingsResponse(activity.Shares(await CallerAsync().ConfigureAwait(false)));

    /// <summary>Cambia la scelta; spenta, cancella le visioni registrate. 400 senza ShareActivity.</summary>
    [HttpPut("Activity/Settings")]
    public async Task<ActionResult> SetSettings([FromBody] ActivitySettings? settings)
    {
        if (settings?.ShareActivity is not { } share)
        {
            return BadRequest();
        }

        activity.SetShare(await CallerAsync().ConfigureAwait(false), share);
        return NoContent();
    }

    /// <summary>La riga "Visti dagli amici".</summary>
    [HttpGet("Activity/FriendsWatched")]
    public async Task<ActionResult<FriendsWatchedResponse>> GetFriendsWatched() =>
        activity.FriendsWatched(await CallerAsync().ConfigureAwait(false));

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
