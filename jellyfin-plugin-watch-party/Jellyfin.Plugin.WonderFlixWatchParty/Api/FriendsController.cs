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
/// Endpoint degli amici (spec F §6.7). Chi chiama è l'utente
/// dell'autenticazione. Come il resto del plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class FriendsController(
    IAuthorizationContext authorizationContext,
    FriendService friends,
    PartyService parties) : ControllerBase
{
    /// <summary>Amici con il loro stato (e il party visibile in cui stanno), richieste in arrivo e inviate.</summary>
    [HttpGet("Friends")]
    public async Task<ActionResult<FriendsResponse>> GetFriends()
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        var userName = auth.User?.Username ?? string.Empty;
        return friends.GetFriends(auth.UserId, friendId => parties.PartyOf(auth.UserId, userName, friendId));
    }

    /// <summary>Utenti il cui nome contiene q (almeno 2 lettere), al massimo 10.</summary>
    [HttpGet("Users/Search")]
    public async Task<ActionResult<IReadOnlyList<UserSearchResult>>> Search([FromQuery] string? q)
    {
        var result = friends.Search(await CallerAsync().ConfigureAwait(false), q);
        return result.Status == HubStatus.Ok ? Ok(result.Value) : Failure(result.Status);
    }

    [HttpPost("Friends/Requests/{userId:guid}")]
    public async Task<ActionResult> SendRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.RequestAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpPost("Friends/Requests/{userId:guid}/Accept")]
    public async Task<ActionResult> AcceptRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.AcceptAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpPost("Friends/Requests/{userId:guid}/Decline")]
    public async Task<ActionResult> DeclineRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.DeclineAsync(caller, userId).ConfigureAwait(false));
    }

    /// <summary>Annulla la propria richiesta a userId.</summary>
    [HttpDelete("Friends/Requests/{userId:guid}")]
    public async Task<ActionResult> CancelRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.CancelAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpDelete("Friends/{userId:guid}")]
    public async Task<ActionResult> RemoveFriend([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.RemoveAsync(caller, userId).ConfigureAwait(false));
    }

    /// <summary>204 se riuscita, altrimenti il codice dell'esito.</summary>
    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Ok => NoContent(),
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
        HubStatus.Conflict => Conflict(),
        HubStatus.RateLimited => StatusCode(StatusCodes.Status429TooManyRequests),
        _ => BadRequest(),
    };

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
