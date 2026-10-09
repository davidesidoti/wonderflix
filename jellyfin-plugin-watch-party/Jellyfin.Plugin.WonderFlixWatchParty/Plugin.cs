using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Plugin "WonderFlix Watch Party" (spec E, F, G): nomi, chat e reazioni nei
/// watch party SyncPlay di WonderFlix, gli amici e la cassetta delle
/// notifiche. Ha una sola impostazione, NotifyNewTitles; la sua pagina nella
/// Dashboard serve per quella, per gli annunci e per mandare subito i nuovi
/// titoli (spec G §6.8). Dalla 1.6.0 anche il recupero della password (spec L):
/// la stessa pagina ha le impostazioni di Discord, dell'email e dei promemoria.
/// </summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    /// <summary>Id del plugin, uguale in meta.json e manifest.json.</summary>
    public static readonly Guid PluginId = Guid.Parse("882eb47e-668a-4935-ba55-c2858eb4ed90");

    /// <summary>
    /// L'istanza creata da Jellyfin, che non la mette nel DI: da qui si legge
    /// la configurazione di adesso (<see cref="Server.PluginNewTitlesSettings"/>).
    /// </summary>
    public static Plugin? Instance { get; private set; }

    /// <summary>
    /// La pagina nella Dashboard (menu laterale, sotto Plugin). Name deve
    /// essere unico tra tutti i plugin: Jellyfin cerca la pagina per nome.
    /// </summary>
    internal static readonly IReadOnlyList<PluginPageInfo> Pages =
    [
        new PluginPageInfo
        {
            Name = "WonderFlixWatchParty",
            DisplayName = "WonderFlix Watch Party",
            EmbeddedResourcePath = typeof(Plugin).Namespace + ".Configuration.configPage.html",
            EnableInMainMenu = true,
        },
    ];

    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    public override string Name => "WonderFlix Watch Party";

    public override Guid Id => PluginId;

    public override string Description =>
        "Names, chat, reactions, friends, notifications and password recovery for SyncPlay watch parties in WonderFlix.";

    public IEnumerable<PluginPageInfo> GetPages() => Pages;
}
