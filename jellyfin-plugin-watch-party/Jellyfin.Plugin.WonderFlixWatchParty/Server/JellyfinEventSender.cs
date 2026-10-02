using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Inoltro come GeneralCommand SendString sul WebSocket della sessione
/// (spec E §6.7).
/// </summary>
public sealed class JellyfinEventSender(ISessionManager sessionManager) : IEventSender
{
    public async Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken)
    {
        var command = new GeneralCommand
        {
            Name = GeneralCommandType.SendString,
            Arguments = { [WatchPartyProtocol.ArgumentKey] = payload },
        };
        try
        {
            // Senza una sessione che comanda il server non controlla i
            // permessi di controllo remoto; senza WebSocket aperto non manda
            // nulla.
            await sessionManager.SendGeneralCommand(null, sessionId, command, cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (ResourceNotFoundException)
        {
            return false;
        }
    }
}
