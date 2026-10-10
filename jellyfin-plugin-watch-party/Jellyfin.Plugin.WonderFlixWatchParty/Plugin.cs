using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Plugin "WonderFlix Watch Party" (spec E, F, G): nomi, chat e reazioni nei
/// watch party SyncPlay di WonderFlix, gli amici e la cassetta delle
/// notifiche. Le impostazioni sono i nuovi titoli (NotifyNewTitles), Seerr e,
/// dalla 1.6.0, il recupero della password (spec L: Discord, email e
/// promemoria) e, dalla 1.7.0, la Home su misura (spec M: la Home dell'admin
/// e le uscite di Sonarr e Radarr). La sua pagina nella Dashboard serve per
/// queste, per gli annunci e per mandare subito i nuovi titoli (spec G §6.8).
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
        "Names, chat, reactions, friends, notifications, password recovery and the Home rows (upcoming from Sonarr and Radarr) for WonderFlix.";

    public IEnumerable<PluginPageInfo> GetPages() => Pages;
}
