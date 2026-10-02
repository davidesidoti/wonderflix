using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Session;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>Endpoint del plugin (spec E §6.2).</summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class WatchPartyController(
    IAuthorizationContext authorizationContext,
    ISessionManager sessionManager) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin e del protocollo.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(PluginVersion, WatchPartyProtocol.Version);

    /// <summary>
    /// Sonda provvisoria (piano 10a, Task 2): manda un SendString alla
    /// sessione di chi chiama. Si toglie nel Task 6.
    /// </summary>
    [HttpPost("Probe")]
    public async Task<ActionResult> Probe(CancellationToken cancellationToken)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.DeviceId, auth.DeviceId, StringComparison.Ordinal)
            && string.Equals(s.Client, auth.Client, StringComparison.Ordinal)
            && s.UserId.Equals(auth.UserId));
        if (session is null)
        {
            return Conflict();
        }

        var command = new GeneralCommand
        {
            Name = GeneralCommandType.SendString,
            Arguments = { [WatchPartyProtocol.ArgumentKey] = "{\"Probe\":1}" },
        };
        await sessionManager.SendGeneralCommand(null, session.Id, command, cancellationToken).ConfigureAwait(false);
        return Ok(new { SessionId = session.Id, session.Client });
    }
}
