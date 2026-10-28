using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I download automatici visti dall'admin (spec T §7.4, §8): panoramica, ricerca dal vivo, "scarica", "va bene così",
/// "cerca adesso" e i profili. Una chiave o un corpo non validi sono 400; 409 con {Reason} per "Expired" e "Busy",
/// 503 {Reason:"Unavailable"} se Radarr/Sonarr non rispondono (ruling 7 e 8).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Downloads")]
[Authorize(Policy = Policies.RequiresElevation)]
[Produces(MediaTypeNames.Application.Json)]
public class DownloadsController(DownloadService downloads) : ControllerBase
{
    [HttpGet]
    public ActionResult<DownloadsOverviewDto> Overview() => downloads.Overview();

    /// <summary>Ricerca dal vivo (fino a 2 minuti); 400 per una chiave non valida o un titolo che non c'è.</summary>
    [HttpGet("Search")]
    public async Task<ActionResult<DownloadSearchDto>> Search([FromQuery] string? key)
    {
        var result = await downloads.SearchAsync(key ?? string.Empty, HttpContext.RequestAborted).ConfigureAwait(false);
        return result is null ? BadRequest() : result;
    }

    /// <summary>Scarica una release della ricerca; 204.</summary>
    [HttpPost("Grab")]
    public async Task<ActionResult> Grab([FromBody] GrabRequest? request)
    {
        if (string.IsNullOrEmpty(request?.Key) || string.IsNullOrWhiteSpace(request.Guid) || request.IndexerId <= 0)
        {
            return BadRequest();
        }

        return await downloads.GrabAsync(request.Key, request.Guid, request.IndexerId, HttpContext.RequestAborted).ConfigureAwait(false) switch
        {
            GrabOutcome.Ok => NoContent(),
            GrabOutcome.Expired => Error(StatusCodes.Status409Conflict, "Expired"),
            GrabOutcome.Busy => Error(StatusCodes.Status409Conflict, "Busy"),
            GrabOutcome.Unavailable => Error(StatusCodes.Status503ServiceUnavailable, "Unavailable"),
            _ => BadRequest(),
        };
    }

    /// <summary>"Va bene così": 204.</summary>
    [HttpPost("Accept")]
    public ActionResult Accept([FromBody] KeyRequest? request) =>
        request?.Key is { } key && downloads.Accept(key) ? NoContent() : BadRequest();

    /// <summary>"Cerca adesso": 202, la ricerca parte al prossimo giro, chiesto subito.</summary>
    [HttpPost("SearchNow")]
    public ActionResult SearchNow([FromBody] KeyRequest? request) =>
        request?.Key is { } key && downloads.SearchNow(key) ? Accepted() : BadRequest();

    /// <summary>I profili di qualità con le loro soglie, per la pagina di configurazione.</summary>
    [HttpGet("Profiles")]
    public async Task<ActionResult<IReadOnlyList<DownloadProfileDto>>> Profiles() =>
        new ActionResult<IReadOnlyList<DownloadProfileDto>>(
            await downloads.ProfilesAsync(HttpContext.RequestAborted).ConfigureAwait(false));

    private static ObjectResult Error(int status, string reason) =>
        new(new DownloadsErrorDto(reason)) { StatusCode = status };
}
