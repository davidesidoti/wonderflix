using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Legge il riavvio richiesto dal server; <c>HasPendingRestart</c> (su IApplicationHost) esiste in 10.11.0 e in 10.11.9.</summary>
public sealed class JellyfinRestartState(IServerApplicationHost host) : IRestartState
{
    public bool PendingRestart => host.HasPendingRestart;
}
