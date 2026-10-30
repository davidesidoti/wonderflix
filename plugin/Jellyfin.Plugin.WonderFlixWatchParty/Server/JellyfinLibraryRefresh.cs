using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Chiede a Jellyfin la scansione della libreria; <c>QueueLibraryScan</c> esiste in 10.11.0 e in 10.11.9.</summary>
public sealed class JellyfinLibraryRefresh(ILibraryManager libraryManager) : ILibraryRefresh
{
    public void Refresh() => libraryManager.QueueLibraryScan();
}
