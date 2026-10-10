using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// La Home dell'admin (spec M §7.2): ogni utente collegato la legge, solo
/// l'admin la scrive (dalla dashboard admin dell'app).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Home")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class HomeController(IHomeLayoutStore layout) : ControllerBase
{
    [HttpGet("Layout")]
    public ActionResult<HomeLayoutDto> GetLayout() => new HomeLayoutDto(layout.Rows);

    /// <summary>Salva la Home dell'admin, senza gli id sconosciuti e i doppioni; risponde con quella salvata.</summary>
    [HttpPost("Layout")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<HomeLayoutDto> SetLayout([FromBody] HomeLayoutRequest? request)
    {
        if (request is null)
        {
            return BadRequest();
        }

        layout.Save(request.Rows is null ? null : HomeRowIds.Normalize(request.Rows));
        return new HomeLayoutDto(layout.Rows);
    }
}
