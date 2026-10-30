namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Chiede a Jellyfin di rileggere la libreria dopo una cancellazione (spec U §6).</summary>
public interface ILibraryRefresh
{
    /// <summary>Mette in coda una scansione della libreria; ritorna subito.</summary>
    void Refresh();
}
