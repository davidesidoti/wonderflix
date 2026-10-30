using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Lo spazio del seedbox visto dall'admin (spec U §7.4): panoramica per chi chiama, nuovo calcolo, operazioni e il loro
/// avanzamento, titoli tenuti e torrent in attesa. Errori come per i download: {Reason}.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Space")]
[Authorize(Policy = Policies.RequiresElevation)]
[Produces(MediaTypeNames.Application.Json)]
public class SpaceController(SpaceService space, IAuthorizationContext authorizationContext) : ControllerBase
{
    /// <summary>La panoramica per chi chiama; con una chiave API senza utente <c>Guid.Empty</c>: nessun preferito tolto, niente generi.</summary>
    [HttpGet]
    public async Task<ActionResult<SpaceOverviewDto>> Overview() =>
        await space.OverviewAsync(
            (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId,
            HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>Un nuovo calcolo, senza aspettarlo: 202. Il suo errore lo gestisce il servizio.</summary>
    [HttpPost("Recalculate")]
    public ActionResult Recalculate()
    {
        _ = space.ScanAsync(CancellationToken.None);
        return Accepted();
    }

    /// <summary>Mette in coda un'operazione: 202 {Id}; 400, 404 {Unknown}, 409 {Busy} o {NotReady}.</summary>
    [HttpPost("Operations")]
    public ActionResult<SpaceStartedDto> Start([FromBody] StartOperationRequest? request)
    {
        if (string.IsNullOrEmpty(request?.Kind) || string.IsNullOrEmpty(request.Key))
        {
            return BadRequest();
        }

        return space.Start(request.Kind, request.Key) switch
        {
            (SpaceService.StartOutcome.Started, var id) => Accepted(new SpaceStartedDto(id!)),
            (SpaceService.StartOutcome.Unknown, _) => Error(StatusCodes.Status404NotFound, "Unknown"),
            (SpaceService.StartOutcome.Busy, _) => Error(StatusCodes.Status409Conflict, "Busy"),
            (SpaceService.StartOutcome.NotReady, _) => Error(StatusCodes.Status409Conflict, "NotReady"),
            _ => BadRequest(),
        };
    }

    /// <summary>I passi di un'operazione; 404 se non c'è.</summary>
    [HttpGet("Operations/{id}")]
    public ActionResult<SpaceOperationDto> Operation(string id) =>
        space.Operation(id) is { } operation ? operation : NotFound();

    /// <summary>"Tienilo": 204. La chiave è un film, una serie o una stagione (spec U §6.4).</summary>
    [HttpPost("Kept")]
    public ActionResult Keep([FromBody] KeepRequest? request)
    {
        if (request?.Key is not { } key
            || !(SpaceService.IsValidKey(SpaceKinds.Movie, key) || SpaceService.IsValidKey(SpaceKinds.Series, key)
                || SpaceService.IsValidKey(SpaceKinds.Season, key)))
        {
            return BadRequest();
        }

        space.Keep(key, request.Title ?? string.Empty);
        return NoContent();
    }

    /// <summary>Toglie un titolo dai tenuti: 204.</summary>
    [HttpDelete("Kept")]
    public ActionResult Unkeep([FromQuery] string? key)
    {
        if (string.IsNullOrEmpty(key))
        {
            return BadRequest();
        }

        space.Unkeep(key);
        return NoContent();
    }

    /// <summary>Toglie un torrent dall'attesa e lo lascia in qBittorrent: 204, 404 se non c'è.</summary>
    [HttpDelete("Pending/{hash}")]
    public ActionResult DropPending(string hash) => space.DropPending(hash) ? NoContent() : NotFound();

    private static ObjectResult Error(int status, string reason) => new(new SpaceErrorDto(reason)) { StatusCode = status };
}
