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

    /// <summary>
    /// Una serie o una stagione vera tolta (con una cartella, non virtuale).
    /// Con la cartella rinominata Jellyfin toglie solo lei, e i suoi episodi
    /// tornano con id nuovi e i dati utente di prima: non sono nuovi. Dà la
    /// chiave della serie (quella degli episodi) e il numero della stagione;
    /// null vale per tutta la serie, anche per una stagione senza numero:
    /// meglio non annunciare che annunciare episodi già visti. O(1), per il
    /// gestore dell'evento.
    /// </summary>
    public static bool TryGetRemovedContainer(BaseItem? item, out string seriesKey, out int? season)
    {
        seriesKey = string.Empty;
        season = null;
        if (item is null || item.IsVirtualItem || string.IsNullOrEmpty(item.Path))
        {
            return false;
        }

        if (item is Series series)
        {
            seriesKey = series.PresentationUniqueKey ?? string.Empty;
        }
        else if (item is Season seasonItem)
        {
            seriesKey = seasonItem.SeriesPresentationUniqueKey ?? seasonItem.FindSeriesPresentationUniqueKey() ?? string.Empty;
            season = seasonItem.IndexNumber;
        }

        return seriesKey.Length > 0;
    }

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
