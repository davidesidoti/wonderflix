using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ServiceRegistrationTests
{
    [Fact]
    public void AllServicesResolve()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(InterfaceStub<ISessionManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<ISyncPlayManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IUserManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<ILibraryManager>.Create().Proxy);
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.GetTempPath();
        services.AddSingleton(paths);

        new PluginServiceRegistrator().RegisterServices(services, null!);
        using var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetRequiredService<FriendService>());
        Assert.NotNull(provider.GetRequiredService<PresenceTracker>());
        Assert.NotNull(provider.GetRequiredService<PartyService>());
        Assert.Same(provider.GetRequiredService<PartyAnnouncer>(), provider.GetRequiredService<PartyAnnouncer>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "friends.json"),
            provider.GetRequiredService<FriendStore>().FilePath);
        Assert.NotNull(provider.GetRequiredService<InboxService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "inbox.json"),
            provider.GetRequiredService<InboxStore>().FilePath);
        Assert.NotNull(provider.GetRequiredService<NewTitlesCollector>());
        Assert.IsType<Server.PluginNewTitlesSettings>(provider.GetRequiredService<INewTitlesSettings>());
        Assert.NotNull(provider.GetRequiredService<RequestsService>());
        Assert.NotNull(provider.GetRequiredService<RequestWebhookHandler>());
        Assert.IsType<Seerr.SeerrClient>(provider.GetRequiredService<Seerr.ISeerrClient>());
        Assert.IsType<Server.PluginSeerrSettings>(provider.GetRequiredService<Seerr.ISeerrSettings>());
        Assert.Equal(2, provider.GetServices<IHostedService>().Count());
    }
}
