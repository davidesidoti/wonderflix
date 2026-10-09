using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I contatti per il recupero di chi chiama (spec L §7.6), per ogni utente
/// autenticato. Il canale è una stringa nella rotta: uno sconosciuto è
/// 400 Invalid, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class AccountController(IAuthorizationContext authorizationContext, ContactLinking linking) : ControllerBase
{
    /// <summary>I propri contatti verificati e i canali del server.</summary>
    [HttpGet("Contacts")]
    public async Task<ActionResult<ContactsResponse>> GetContacts() =>
        linking.Get(await CallerAsync().ConfigureAwait(false));

    /// <summary>Manda il codice al contatto scritto; 202 con la scadenza.</summary>
    [HttpPost("Contacts/{channel}/Start")]
    public async Task<ActionResult<LinkStartResponse>> Start([FromRoute] string channel, [FromBody] LinkStartRequest? request)
    {
        if (!AccountChannels.TryParse(channel, out var parsed) || request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await linking.StartAsync(
                await CallerAsync().ConfigureAwait(false), parsed, request.Target, request.Language, HttpContext.RequestAborted)
            .ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return StatusCode(StatusCodes.Status202Accepted, result.Value);
    }

    /// <summary>Il codice ricevuto: il contatto è verificato.</summary>
    [HttpPost("Contacts/{channel}/Confirm")]
    public async Task<ActionResult<ContactsResponse>> Confirm([FromRoute] string channel, [FromBody] LinkConfirmRequest? request)
    {
        if (!AccountChannels.TryParse(channel, out var parsed) || request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await linking.ConfirmAsync(await CallerAsync().ConfigureAwait(false), parsed, request.Code)
            .ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return result.Value!;
    }

    /// <summary>Toglie il contatto del canale; 204 anche se non c'era.</summary>
    [HttpDelete("Contacts/{channel}")]
    public async Task<ActionResult> Unlink([FromRoute] string channel)
    {
        if (!AccountChannels.TryParse(channel, out var parsed))
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        linking.Unlink(await CallerAsync().ConfigureAwait(false), parsed);
        return NoContent();
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
