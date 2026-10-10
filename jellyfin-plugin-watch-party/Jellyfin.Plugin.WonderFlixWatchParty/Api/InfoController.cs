using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// GET Info per ogni utente autenticato (spec G §7.2): la cassetta delle
/// notifiche vale anche per chi non ha accesso ai watch party. Non può
/// stare nei controller con la policy SyncPlay: un attributo sul metodo si
/// somma a quello della classe, non lo allarga. "requests" c'è solo con
/// Seerr configurato (spec I §7.1); upcomingSeries e upcomingMovies ci sono
/// solo con Sonarr e Radarr configurati (spec M §7.6).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class InfoController(ISeerrSettings seerr, IArrSettings arr) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(
            PluginVersion,
            WatchPartyProtocol.Version,
            WatchPartyProtocol.FeaturesWith(seerr.IsConfigured(), arr.Sonarr.IsConfigured, arr.Radarr.IsConfigured));
}
