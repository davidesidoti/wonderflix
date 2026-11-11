using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>I trailer dentro l'app: se ce n'è uno, lo scarica sul server e lo serve come mp4. Aperto a ogni utente che ha fatto l'accesso.</summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class TrailersController(IAuthorizationContext authorizationContext, TrailerService trailers) : ControllerBase
{
    /// <summary>C'è un trailer per questo titolo? 400 senza titolo o con un tipo che non è movie/tv.</summary>
    [HttpGet("Trailers/Info")]
    public async Task<ActionResult<TrailerInfoDto>> Info([FromQuery] string? itemId, [FromQuery] int? tmdbId, [FromQuery] string? type) =>
        Subject(new TrailerSubjectRequest { ItemId = itemId, TmdbId = tmdbId, Type = type }) is not { } subject
            ? BadRequest()
            : await trailers.InfoAsync(await CallerAsync().ConfigureAwait(false), subject, HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>Avvia il download del trailer (una volta sola per tutti) e dà lo stato.</summary>
    [HttpPost("Trailers/Start")]
    public async Task<ActionResult<TrailerStatusDto>> Start([FromBody] TrailerSubjectRequest? request) =>
        Subject(request) is not { } subject
            ? BadRequest()
            : await trailers.StartAsync(await CallerAsync().ConfigureAwait(false), subject, HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>Lo stato del download; 404 se la chiave non è uscita da Info o Start.</summary>
    [HttpGet("Trailers/Status")]
    public ActionResult<TrailerStatusDto> Status([FromQuery] string? key) =>
        key is not null && trailers.Status(key) is { } status ? status : NotFound();

    /// <summary>Il file mp4, con i range per il seek. La lease lo tiene al sicuro dalla pulizia finché la risposta non finisce.</summary>
    [HttpGet("Trailers/{key}/Stream")]
    [Produces("video/mp4")]
    public ActionResult Stream([FromRoute] string key)
    {
        if (trailers.OpenStream(key) is not var (path, lease))
        {
            return NotFound();
        }

        HttpContext.Response.RegisterForDispose(lease);
        return PhysicalFile(path, "video/mp4", enableRangeProcessing: true);
    }

    // null = richiesta sbagliata: né itemId né tmdbId, itemId che non è un Guid, o un tipo che non è movie/tv.
    private static TrailerSubject? Subject(TrailerSubjectRequest? request)
    {
        if (request is null)
        {
            return null;
        }

        Guid? itemId = null;
        if (!string.IsNullOrEmpty(request.ItemId))
        {
            if (!Guid.TryParse(request.ItemId, out var parsed))
            {
                return null;
            }

            itemId = parsed;
        }

        if (itemId is null && request.TmdbId is null)
        {
            return null;
        }

        if (request.Type is not null && request.Type != RequestMediaTypes.Movie && request.Type != RequestMediaTypes.Tv)
        {
            return null;
        }

        return itemId is null && request.Type is null ? null : new TrailerSubject(itemId, request.Type, request.TmdbId);
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
