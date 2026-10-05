using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il webhook di Seerr (spec I §7.5): senza accesso Jellyfin, protetto dal
/// segreto nel corpo. Solo 401 (segreto) o 200: mai altro, così Seerr non
/// insiste con gli eventi che il plugin scarta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Requests")]
[AllowAnonymous]
public class RequestsWebhookController(RequestWebhookHandler handler) : ControllerBase
{
    [HttpPost("Webhook")]
    [RequestSizeLimit(RequestWebhookHandler.MaxBodyBytes)]
    public async Task<ActionResult> Receive([FromBody] SeerrWebhookPayload? payload) =>
        await handler.HandleAsync(payload, HttpContext.RequestAborted).ConfigureAwait(false) == WebhookResult.Unauthorized
            ? Unauthorized()
            : (ActionResult)Ok();
}
