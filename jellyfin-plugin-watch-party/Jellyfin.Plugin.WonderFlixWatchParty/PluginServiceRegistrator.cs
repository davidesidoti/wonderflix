using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>Registra i servizi del plugin nel server.</summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        // Jellyfin non registra un TimeProvider.
        serviceCollection.TryAddSingleton(TimeProvider.System);
        serviceCollection.AddSingleton<ISessionDirectory, JellyfinSessionDirectory>();
        serviceCollection.AddSingleton<IGroupDirectory, JellyfinGroupDirectory>();
        serviceCollection.AddSingleton<IEventSender, JellyfinEventSender>();
        serviceCollection.AddSingleton<PartyRegistry>();
        serviceCollection.AddSingleton<ChatHistory>();
        serviceCollection.AddSingleton<RateLimiter>();
        serviceCollection.AddSingleton<PartyHub>();
        serviceCollection.AddHostedService<WatchPartyHostedService>();
    }
}
