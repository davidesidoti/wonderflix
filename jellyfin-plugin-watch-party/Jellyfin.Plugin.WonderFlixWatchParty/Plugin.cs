using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Plugin "WonderFlix Watch Party" (spec E): nomi, chat e reazioni nei
/// watch party SyncPlay di WonderFlix. Non ha impostazioni.
/// </summary>
public class Plugin : BasePlugin<BasePluginConfiguration>
{
    /// <summary>Id del plugin, uguale in meta.json e manifest.json.</summary>
    public static readonly Guid PluginId = Guid.Parse("882eb47e-668a-4935-ba55-c2858eb4ed90");

    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
    }

    public override string Name => "WonderFlix Watch Party";

    public override Guid Id => PluginId;

    public override string Description => "Names, chat and reactions for SyncPlay watch parties in WonderFlix.";
}
