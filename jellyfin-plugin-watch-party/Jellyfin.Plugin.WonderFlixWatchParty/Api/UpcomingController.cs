using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le uscite in arrivo per la Home (spec M §7.3): ogni utente collegato le
/// legge, sempre con 200 (un problema è in "Error"); la prova del
/// collegamento è solo per gli admin.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Upcoming")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class UpcomingController(
    IAuthorizationContext authorizationContext,
    UpcomingService upcoming) : ControllerBase
{
    /// <summary>Gli episodi in arrivo, con la serie di Jellyfin solo se chi chiama la vede.</summary>
    [HttpGet("Series")]
    public async Task<ActionResult<UpcomingSeriesResponse>> GetSeries()
    {
        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        return await upcoming.GetSeriesAsync(caller, HttpContext.RequestAborted).ConfigureAwait(false);
    }

    [HttpGet("Movies")]
    public async Task<ActionResult<UpcomingMoviesResponse>> GetMovies() =>
        await upcoming.GetMoviesAsync(HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>"Prova collegamento" della dashboard admin e della pagina del plugin.</summary>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<UpcomingTestResponse>> Test() =>
        await upcoming.TestAsync(HttpContext.RequestAborted).ConfigureAwait(false);
}
