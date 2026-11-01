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
    public async Task<ActionResult<DownloadsOverviewDto>> Overview() =>
        await downloads.OverviewAsync(HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>
    /// Ricerca dal vivo: avvia o raggiunge il job del titolo e ne aspetta la fine (fino a 15 minuti), per le app 0.27 e prima
    /// (le nuove usano SearchStart e SearchStatus); 400 per una chiave non valida o un titolo che non c'è.
    /// </summary>
    [HttpGet("Search")]
    public async Task<ActionResult<DownloadSearchDto>> Search([FromQuery] string? key)
    {
        var result = await downloads.SearchAsync(key ?? string.Empty, HttpContext.RequestAborted).ConfigureAwait(false);
        return result is null ? BadRequest() : result;
    }

    /// <summary>
    /// Avvia (o riprende) la ricerca in background del titolo e risponde subito con lo stato (spec W §4.4);
    /// Again=false lascia stare un job in corso o finito da meno di 30 minuti. 400 per una chiave mancante o non valida.
    /// </summary>
    [HttpPost("SearchStart")]
    public ActionResult<DownloadSearchStatusDto> SearchStart([FromBody] SearchStartRequest? request) =>
        request?.Key is { } key && downloads.StartSearch(key, request.Again) is { } status ? status : BadRequest();

    /// <summary>Lo stato della ricerca in background del titolo (spec W §4.4); 400 per una chiave non valida.</summary>
    [HttpGet("SearchStatus")]
    public ActionResult<DownloadSearchStatusDto> SearchStatus([FromQuery] string? key) =>
        downloads.SearchStatus(key ?? string.Empty) is { } status ? status : BadRequest();

    /// <summary>Scarica una release della ricerca; 204.</summary>
    [HttpPost("Grab")]
    public async Task<ActionResult> Grab([FromBody] GrabRequest? request)
    {
        if (string.IsNullOrEmpty(request?.Key) || string.IsNullOrWhiteSpace(request.Guid) || request.IndexerId <= 0)
        {
            return BadRequest();
        }

        return Result(await downloads.GrabAsync(request.Key, request.Guid, request.IndexerId, HttpContext.RequestAborted, request.Lighten).ConfigureAwait(false));
    }

    /// <summary>"Scarica il migliore intanto" (fino a 2 minuti): 204; 409 NothingToGrab, poi gli errori di Grab.</summary>
    [HttpPost("GrabBest")]
    public async Task<ActionResult> GrabBest([FromBody] KeyRequest? request) =>
        request?.Key is { } key ? Result(await downloads.GrabBestAsync(key, HttpContext.RequestAborted).ConfigureAwait(false)) : BadRequest();

    /// <summary>"Va bene, aspetto": 204; 400 se la voce non è in "Serve te" per "nessun file valido".</summary>
    [HttpPost("Snooze")]
    public ActionResult Snooze([FromBody] KeyRequest? request) =>
        request?.Key is { } key && downloads.Snooze(key) ? NoContent() : BadRequest();

    /// <summary>"Importa comunque": 204; 409 Changed se non è più bloccata; 502 NoFiles o ImportFailed.</summary>
    [HttpPost("Import")]
    public async Task<ActionResult> Import([FromBody] KeyRequest? request)
    {
        if (request?.Key is not { } key)
        {
            return BadRequest();
        }

        var (outcome, error) = await downloads.ImportBlockedAsync(key).ConfigureAwait(false);
        return outcome == BlockedOutcome.Failed
            ? Error(StatusCodes.Status502BadGateway, error == "NoFiles" ? error : "ImportFailed")
            : Result(outcome);
    }

    /// <summary>"Scarta e cerca un altro": 204; 409 Changed se non è più bloccata; 503 se Radarr/Sonarr non rispondono.</summary>
    [HttpPost("Discard")]
    public async Task<ActionResult> Discard([FromBody] KeyRequest? request) =>
        request?.Key is { } key ? Result(await downloads.DiscardBlockedAsync(key).ConfigureAwait(false)) : BadRequest();

    private ActionResult Result(GrabOutcome outcome) => outcome switch
    {
        GrabOutcome.Ok => NoContent(),
        GrabOutcome.Expired => Error(StatusCodes.Status409Conflict, "Expired"),
        GrabOutcome.Busy => Error(StatusCodes.Status409Conflict, "Busy"),
        GrabOutcome.NothingToGrab => Error(StatusCodes.Status409Conflict, "NothingToGrab"),
        GrabOutcome.Refused => Error(StatusCodes.Status502BadGateway, "Refused"),
        GrabOutcome.Unavailable => Error(StatusCodes.Status503ServiceUnavailable, "Unavailable"),
        GrabOutcome.Invalid => BadRequest(),
        _ => throw new InvalidOperationException("GrabOutcome sconosciuto"),
    };

    private ActionResult Result(BlockedOutcome outcome) => outcome switch
    {
        BlockedOutcome.Ok => NoContent(),
        BlockedOutcome.Changed => Error(StatusCodes.Status409Conflict, "Changed"),
        BlockedOutcome.Unavailable => Error(StatusCodes.Status503ServiceUnavailable, "Unavailable"),
        BlockedOutcome.Invalid => BadRequest(),
        _ => throw new InvalidOperationException("BlockedOutcome sconosciuto"),
    };

    /// <summary>"Va bene così": 204.</summary>
    [HttpPost("Accept")]
    public ActionResult Accept([FromBody] KeyRequest? request) =>
        request?.Key is { } key && downloads.Accept(key) ? NoContent() : BadRequest();

    /// <summary>"Cerca adesso": 202, la ricerca parte al prossimo giro, chiesto subito.</summary>
    [HttpPost("SearchNow")]
    public ActionResult SearchNow([FromBody] KeyRequest? request) =>
        request?.Key is { } key && downloads.SearchNow(key) ? Accepted() : BadRequest();

    /// <summary>"Cerca un upgrade" da "Da ripassare": 204; 409 Changed se non è più da ripassare né da cercare.</summary>
    [HttpPost("Hunt")]
    public ActionResult Hunt([FromBody] KeyRequest? request) => (request?.Key is { } key ? downloads.Hunt(key) : HuntOutcome.Invalid) switch
    {
        HuntOutcome.Ok => NoContent(),
        HuntOutcome.Changed => Error(StatusCodes.Status409Conflict, "Changed"),
        _ => BadRequest(),
    };

    /// <summary>I profili di qualità con le loro soglie, per la pagina di configurazione; 503 se nessun servizio configurato risponde.</summary>
    [HttpGet("Profiles")]
    public async Task<ActionResult<IReadOnlyList<DownloadProfileDto>>> Profiles() =>
        await downloads.ProfilesAsync(HttpContext.RequestAborted).ConfigureAwait(false) is { } profiles
            ? new ActionResult<IReadOnlyList<DownloadProfileDto>>(profiles)
            : Error(StatusCodes.Status503ServiceUnavailable, "Unavailable");

    private static ObjectResult Error(int status, string reason) =>
        new(new DownloadsErrorDto(reason)) { StatusCode = status };
}
