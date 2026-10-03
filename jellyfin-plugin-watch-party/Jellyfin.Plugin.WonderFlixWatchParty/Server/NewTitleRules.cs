using System.Diagnostics.CodeAnalysis;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Quali elementi di Jellyfin sono "titoli" per il riepilogo dei nuovi titoli (spec G §6.6).</summary>
public static class NewTitleRules
{
    private static readonly MetadataProvider[] Providers =
        [MetadataProvider.Tmdb, MetadataProvider.Imdb, MetadataProvider.Tvdb];

    /// <summary>
    /// Un film o un episodio vero: non un segnaposto "mancante"
    /// (IsVirtualItem, li crea il plugin TVDB), con un file, non un extra né
    /// un trailer. Vale anche per i tolti: TVDB toglie il segnaposto quando
    /// arriva l'episodio vero, con lo stesso id TVDB, e non deve sembrare una
    /// sostituzione.
    /// </summary>
    public static bool IsRealTitle([NotNullWhen(true)] BaseItem? item) =>
        item is Movie or Episode
        && !item.IsVirtualItem
        && !string.IsNullOrEmpty(item.Path)
        && item.ExtraType is null
        && item.OwnerId == Guid.Empty;

    /// <summary>Gli id esterni TMDB, IMDb e TVDB, come "Tmdb:438631".</summary>
    public static IReadOnlyCollection<string> ExternalKeys(BaseItem item)
    {
        var keys = new List<string>();
        foreach (var provider in Providers)
        {
            if (item.TryGetProviderId(provider, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                keys.Add($"{provider}:{value.Trim()}");
            }
        }

        return keys;
    }
}
