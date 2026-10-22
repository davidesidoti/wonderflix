using System.Globalization;
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
    UpcomingService upcoming,
    CalendarService calendar) : ControllerBase
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

    /// <summary>Il calendario delle uscite da <c>start</c> a <c>end</c> escluso (spec S §6.1); 400 se il periodo non è valido.</summary>
    [HttpGet("Calendar")]
    public async Task<ActionResult<CalendarResponse>> GetCalendar([FromQuery] string? start, [FromQuery] string? end)
    {
        if (!DateOnly.TryParseExact(start, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var from)
            || !DateOnly.TryParseExact(end, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var to)
            || !CalendarService.IsValidPeriod(from, to))
        {
            return BadRequest();
        }

        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        return await calendar.GetAsync(caller, from, to, HttpContext.RequestAborted).ConfigureAwait(false);
    }

    /// <summary>"Prova collegamento" della dashboard admin e della pagina del plugin.</summary>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<UpcomingTestResponse>> Test() =>
        await upcoming.TestAsync(HttpContext.RequestAborted).ConfigureAwait(false);
}
