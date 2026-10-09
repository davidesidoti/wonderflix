using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il recupero visto dall'admin (spec L §7.6): utenti, codice, scollegamento,
/// stato e prova. L'id dell'utente è una stringa nella rotta: uno non
/// valido o sconosciuto è 400 UnknownUser, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account/Admin")]
[Authorize(Policy = Policies.RequiresElevation)]
[Produces(MediaTypeNames.Application.Json)]
public class AccountAdminController(
    IAuthorizationContext authorizationContext,
    AccountAdmin admin,
    PasswordRecovery recovery) : ControllerBase
{
    [HttpGet("Users")]
    public ActionResult<List<AdminUserDto>> GetUsers() => admin.Users();

    /// <summary>Manda un codice di recupero all'utente; la risposta dice dove è arrivato.</summary>
    [HttpPost("Users/{userId}/Recovery")]
    public async Task<ActionResult<AdminRecoveryResponse>> SendRecovery(
        [FromRoute] string userId, [FromBody] AccountLanguageRequest? request)
    {
        if (!Guid.TryParse(userId, out var id))
        {
            return AccountErrors.Result(AccountError.UnknownUser);
        }

        var result = await recovery.SendForAdminAsync(
                id, await CallerAsync().ConfigureAwait(false), request?.Language, HttpContext.RequestAborted)
            .ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return result.Value!;
    }

    /// <summary>Toglie Discord ed email dell'utente e annulla un codice di recupero già mandato; 204.</summary>
    [HttpDelete("Users/{userId}/Contacts")]
    public async Task<ActionResult> Unlink([FromRoute] string userId)
    {
        if (!Guid.TryParse(userId, out var id))
        {
            return AccountErrors.Result(AccountError.UnknownUser);
        }

        return admin.Unlink(id, await CallerAsync().ConfigureAwait(false)) is { } error
            ? AccountErrors.Result(error)
            : NoContent();
    }

    [HttpGet("Status")]
    public ActionResult<AccountStatusResponse> Status() => admin.Status();

    /// <summary>Un messaggio di prova per canale (Dashboard e app).</summary>
    [HttpPost("Test")]
    public async Task<ActionResult<AccountTestResponse>> Test([FromBody] AccountTestRequest? request)
    {
        return await admin.TestAsync(
                await CallerAsync().ConfigureAwait(false), request?.Language, request?.Discord, request?.Email, HttpContext.RequestAborted)
            .ConfigureAwait(false);
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
