using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Cerca, scarica e carica sottotitoli (spec R §6.4). La classe ha [Authorize] senza policy:
/// il permesso (admin o spunta sottotitoli) lo controlla SubtitleService a ogni chiamata,
/// 403 se manca. Mai 404; 502 se Jellyfin o un provider falliscono.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class SubtitlesController(
    IAuthorizationContext authorizationContext,
    SubtitleService subtitles) : ControllerBase
{
    /// <summary>Cerca sottotitoli nei provider; 502 senza corpo se la ricerca fallisce.</summary>
    [HttpGet("Subtitles/{itemId}/Search")]
    public async Task<ActionResult<IReadOnlyList<RemoteSubtitleDto>>> Search(
        [FromRoute] string itemId, [FromQuery] string? language, [FromQuery] bool? perfectMatch)
    {
        var result = await subtitles.SearchAsync(
            await CallerAsync().ConfigureAwait(false), itemId, language, perfectMatch, HttpContext.RequestAborted).ConfigureAwait(false);
        return result.Status == SubtitleStatus.Ok ? new OkObjectResult(result.Value) : Error(result.Status, null);
    }

    /// <summary>Scarica un sottotitolo trovato dalla ricerca.</summary>
    [HttpPost("Subtitles/{itemId}/Download")]
    public async Task<ActionResult> Download([FromRoute] string itemId, [FromBody] DownloadSubtitleRequest? request) =>
        Error(
            await subtitles.DownloadAsync(await CallerAsync().ConfigureAwait(false), itemId, request, HttpContext.RequestAborted).ConfigureAwait(false),
            SubtitleReasons.DownloadFailed);

    /// <summary>Carica un file di sottotitoli.</summary>
    [HttpPost("Subtitles/{itemId}/Upload")]
    public async Task<ActionResult> Upload([FromRoute] string itemId, [FromBody] UploadSubtitleRequest? request) =>
        Error(
            await subtitles.UploadAsync(await CallerAsync().ConfigureAwait(false), itemId, request, HttpContext.RequestAborted).ConfigureAwait(false),
            SubtitleReasons.UploadFailed);

    // Ok è 204; reason è il corpo del 502 (la ricerca non ne ha).
    private static ActionResult Error(SubtitleStatus status, string? reason) => status switch
    {
        SubtitleStatus.Ok => new NoContentResult(),
        SubtitleStatus.Forbidden => new StatusCodeResult(StatusCodes.Status403Forbidden),
        SubtitleStatus.Invalid => new BadRequestResult(),
        _ when reason is null => new StatusCodeResult(StatusCodes.Status502BadGateway),
        _ => new ObjectResult(new SubtitleErrorDto(reason)) { StatusCode = StatusCodes.Status502BadGateway },
    };

    // La chiave API non ha un utente: UserId è Guid.Empty e il servizio risponde Forbidden (403).
    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
