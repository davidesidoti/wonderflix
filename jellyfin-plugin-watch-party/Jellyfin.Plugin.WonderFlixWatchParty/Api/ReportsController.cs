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
/// Le segnalazioni (spec R §6). La classe ha [Authorize] senza policy: Create e Mine sono
/// per ogni utente; List e Resolve, per gli admin, hanno RequiresElevation sul metodo
/// (come RatingsAdminController). Mai 404: gli id sono stringhe senza vincoli di rotta,
/// un id non valido è 400; i 409 hanno {Reason}.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class ReportsController(
    IAuthorizationContext authorizationContext,
    ReportService reports) : ControllerBase
{
    /// <summary>Segnala un titolo; un doppione aggiorna la nota.</summary>
    [HttpPost("Reports")]
    public async Task<ActionResult<ReportDto>> Create([FromBody] CreateReportRequest? request)
    {
        var outcome = await reports.CreateAsync(await CallerAsync().ConfigureAwait(false), request).ConfigureAwait(false);
        return outcome.Status == HubStatus.Ok ? new OkObjectResult(outcome.Report) : Error(outcome);
    }

    /// <summary>Le segnalazioni aperte di chi chiama su un titolo.</summary>
    [HttpGet("Reports/Mine")]
    public async Task<ActionResult<ReportListDto>> Mine([FromQuery] string? itemId)
    {
        var result = reports.Mine(await CallerAsync().ConfigureAwait(false), itemId);
        return result.Status == HubStatus.Ok ? new OkObjectResult(result.Value) : BadRequest();
    }

    /// <summary>Tutte le segnalazioni aperte, dalla più recente.</summary>
    [HttpGet("Reports")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<ReportListDto> List() => reports.List();

    /// <summary>Chiude una segnalazione; 409 Closed se non c'è più.</summary>
    [HttpPost("Reports/{reportId}/Resolve")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult> Resolve([FromRoute] string reportId, [FromBody] ResolveReportRequest? request)
    {
        var outcome = await reports.ResolveAsync(await CallerAsync().ConfigureAwait(false), reportId, request).ConfigureAwait(false);
        return outcome.Status == HubStatus.Ok ? new NoContentResult() : Error(outcome);
    }

    private static ActionResult Error(ReportOutcome outcome) => outcome.Status == HubStatus.Conflict
        ? new ObjectResult(new ReportErrorDto(outcome.Reason!)) { StatusCode = StatusCodes.Status409Conflict }
        : new BadRequestResult();

    // La chiave API non ha un utente: UserId è Guid.Empty e il servizio risponde Invalid (400).
    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
