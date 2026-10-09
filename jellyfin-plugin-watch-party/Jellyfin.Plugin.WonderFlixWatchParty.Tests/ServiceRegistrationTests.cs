using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
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
        services.AddSingleton(InterfaceStub<ICollectionManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IImageProcessor>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IAuthorizationContext>.Create().Proxy);
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
        Assert.IsType<Server.JellyfinCollectionDirectory>(provider.GetRequiredService<ICollectionDirectory>());
        Assert.IsType<Server.JellyfinUserAvatars>(provider.GetRequiredService<IUserAvatars>());
        Assert.IsType<Server.PluginAccountSettings>(provider.GetRequiredService<Account.IAccountSettings>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "contacts.json"),
            provider.GetRequiredService<Account.ContactStore>().FilePath);
        Assert.IsType<Server.DiscordBotClient>(provider.GetRequiredService<Account.IDiscordSender>());
        Assert.IsType<Server.SmtpMailSender>(provider.GetRequiredService<Account.IMailSender>());
        Assert.IsType<Server.JellyfinPasswordReset>(provider.GetRequiredService<Account.IPasswordReset>());
        Assert.IsType<Server.JellyfinPasswordCheck>(provider.GetRequiredService<Account.IPasswordCheck>());
        Assert.NotNull(provider.GetRequiredService<Account.ContactLinking>());
        Assert.NotNull(provider.GetRequiredService<Account.AccountAdmin>());
        Assert.NotNull(provider.GetRequiredService<Account.ContactReminders>());

        // Le istanze con stato o lucchetti sono una sola per tutti: due copie dividerebbero i limiti, i codici o i contatti.
        Assert.Same(provider.GetRequiredService<Account.PasswordRecovery>(), provider.GetRequiredService<Account.PasswordRecovery>());
        Assert.Same(provider.GetRequiredService<Account.CodeBook>(), provider.GetRequiredService<Account.CodeBook>());
        Assert.Same(provider.GetRequiredService<Account.ContactRegistry>(), provider.GetRequiredService<Account.ContactRegistry>());
        Assert.Same(provider.GetRequiredService<Account.AccountSender>(), provider.GetRequiredService<Account.AccountSender>());
        Assert.Same(provider.GetRequiredService<Hub.RateLimiter>(), provider.GetRequiredService<Hub.RateLimiter>());

        // I controller del recupero si costruiscono dal DI: una registrazione mancante fa fallire il test, non una richiesta con 500.
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.AccountController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RecoveryController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.AccountAdminController>(provider));

        // Il promemoria dei contatti, oltre ai due di prima.
        Assert.Equal(3, provider.GetServices<IHostedService>().Count());
    }
}
