using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il webhook di Seerr (spec I §7.5): senza accesso Jellyfin, protetto dal
/// segreto nel corpo. Il plugin risponde solo 401 (segreto) o 200, così
/// Seerr non insiste con gli eventi che il plugin scarta. Un corpo
/// malformato, troppo grande o non JSON non arriva al plugin: lo rifiuta
/// ASP.NET stesso con 400, 413 o 415.
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
