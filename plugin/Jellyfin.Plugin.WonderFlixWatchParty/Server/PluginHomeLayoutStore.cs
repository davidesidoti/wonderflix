using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La Home dell'admin nella configurazione del plugin (`HomeRows`).</summary>
public sealed class PluginHomeLayoutStore : IHomeLayoutStore
{
    // Un salvataggio alla volta: due admin che salvano insieme non si mescolano.
    private readonly Lock _lock = new();

    // Si legge ogni volta, come PluginSeerrSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione. Senza
    // plugin (nei test) vale l'ordine predefinito.
    public IReadOnlyList<string>? Rows => HomeRowIds.Parse(Plugin.Instance?.Configuration.HomeRows);

    public void Save(IReadOnlyList<string>? rows)
    {
        var plugin = Plugin.Instance ?? throw new InvalidOperationException("Il plugin non è caricato.");
        lock (_lock)
        {
            plugin.Configuration.HomeRows = rows is null ? null : HomeRowIds.Serialize(rows);
            plugin.SaveConfiguration();
        }
    }

    public bool AddLaterRows()
    {
        // Senza plugin (nei test) non c'è niente da salvare.
        var plugin = Plugin.Instance;
        if (plugin is null)
        {
            return false;
        }

        lock (_lock)
        {
            var config = plugin.Configuration;
            var change = HomeRowIds.WithLaterRows(HomeRowIds.Parse(config.HomeRows), HomeRowIds.ParseSeen(config.HomeRowsSeen));
            if (change is null)
            {
                return false;
            }

            var (rows, seen) = change.Value;
            config.HomeRows = rows is null ? null : HomeRowIds.Serialize(rows);
            config.HomeRowsSeen = HomeRowIds.Serialize(seen);
            plugin.SaveConfiguration();
            return true;
        }
    }
}
