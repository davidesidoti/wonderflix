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
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.GetTempPath();
        services.AddSingleton(paths);

        new PluginServiceRegistrator().RegisterServices(services, null!);
        using var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetRequiredService<FriendService>());
        Assert.NotNull(provider.GetRequiredService<PresenceTracker>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "friends.json"),
            provider.GetRequiredService<FriendStore>().FilePath);
        Assert.Single(provider.GetServices<IHostedService>());
    }
}
