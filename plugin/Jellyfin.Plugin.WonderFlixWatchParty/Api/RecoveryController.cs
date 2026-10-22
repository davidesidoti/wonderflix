using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il recupero della password (spec L §7.6): senza accesso, come il webhook
/// di Seerr. Un controller a parte, perché un [Authorize] sulla classe non
/// si allarga con un attributo sul metodo.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account/Recovery")]
[AllowAnonymous]
[Produces(MediaTypeNames.Application.Json)]
public class RecoveryController(PasswordRecovery recovery) : ControllerBase
{
    /// <summary>Chiede un codice; 202 per tutti, che l'account esista o no.</summary>
    [HttpPost("Start")]
    public ActionResult Start([FromBody] RecoveryStartRequest? request)
    {
        var result = recovery.Start(request?.Username, request?.Language);
        return result.Error is { } error
            ? AccountErrors.Result(error)
            : StatusCode(StatusCodes.Status202Accepted);
    }

    /// <summary>La password nuova con il codice; 204.</summary>
    [HttpPost("Complete")]
    public async Task<ActionResult> Complete([FromBody] RecoveryCompleteRequest? request)
    {
        if (request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await recovery.CompleteAsync(request.Username, request.Code, request.NewPassword, request.Language)
            .ConfigureAwait(false);
        return result.Error is { } error ? AccountErrors.Result(error) : NoContent();
    }
}
