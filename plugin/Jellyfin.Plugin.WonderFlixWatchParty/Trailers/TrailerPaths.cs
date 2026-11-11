using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Le cartelle dei trailer, dentro le configurazioni del plugin (nel container <c>/config</c> è scrivibile).</summary>
public static class TrailerPaths
{
    public static string Root(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, "trailers");

    /// <summary>Qui vive il binario di yt-dlp.</summary>
    public static string Bin(IApplicationPaths paths) => Path.Combine(Root(paths), "bin");

    /// <summary>I trailer scaricati, <c>&lt;id&gt;.mp4</c>.</summary>
    public static string Cache(IApplicationPaths paths) => Path.Combine(Root(paths), "cache");
}
