using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;

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
        serviceCollection.AddSingleton<IUserDirectory, JellyfinUserDirectory>();
        serviceCollection.AddSingleton(provider => new FriendStore(
            FriendStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<FriendStore>>()));
        serviceCollection.AddSingleton<FriendService>();
        serviceCollection.AddSingleton<ILibraryAccess, JellyfinLibraryAccess>();
        serviceCollection.AddSingleton<ICollectionDirectory, JellyfinCollectionDirectory>();
        serviceCollection.AddSingleton<IUserAvatars, JellyfinUserAvatars>();
        serviceCollection.AddSingleton(provider => new InboxStore(
            InboxStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<InboxStore>>()));
        serviceCollection.AddSingleton<InboxService>();
        serviceCollection.AddSingleton<INewTitlesSettings, PluginNewTitlesSettings>();
        serviceCollection.AddSingleton<ISeerrSettings, PluginSeerrSettings>();
        // La chiave API non va nei log del client HTTP e non segue un
        // redirect verso un altro host (.NET toglie solo Authorization).
        serviceCollection.AddHttpClient(SeerrClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false })
            .RedactLoggedHeaders(["X-API-Key"]);
        serviceCollection.AddSingleton<ISeerrClient, SeerrClient>();
        serviceCollection.AddSingleton<SeerrUserMap>();
        serviceCollection.AddSingleton<SeerrTitleCache>();
        serviceCollection.AddSingleton<RequestsService>();
        serviceCollection.AddSingleton<RequestWebhookHandler>();
        // Recupero della password (spec L).
        serviceCollection.AddSingleton<IAccountSettings, PluginAccountSettings>();
        serviceCollection.AddSingleton(provider => new ContactStore(
            ContactStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ContactStore>>()));
        serviceCollection.AddSingleton<ContactRegistry>();
        serviceCollection.AddSingleton<CodeBook>();
        // Il token del bot non va nei log del client HTTP e non segue un redirect.
        serviceCollection.AddHttpClient(DiscordBotClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false })
            .RedactLoggedHeaders(["Authorization"]);
        serviceCollection.AddSingleton<IDiscordSender, DiscordBotClient>();
        serviceCollection.AddSingleton<IMailSender, SmtpMailSender>();
        serviceCollection.AddSingleton<IPasswordReset, JellyfinPasswordReset>();
        serviceCollection.AddSingleton<IPasswordCheck, JellyfinPasswordCheck>();
        serviceCollection.AddSingleton<AccountSender>();
        serviceCollection.AddSingleton<ContactLinking>();
        serviceCollection.AddSingleton<PasswordRecovery>();
        serviceCollection.AddSingleton<AccountAdmin>();
        serviceCollection.AddSingleton<ContactReminders>();
        serviceCollection.AddSingleton<ILibraryTitles, JellyfinLibraryTitles>();
        serviceCollection.AddSingleton<NewTitlesCollector>();
        serviceCollection.AddSingleton<PresenceTracker>();
        serviceCollection.AddSingleton<PartyDirectory>();
        serviceCollection.AddSingleton<PartyAnnouncer>();
        serviceCollection.AddSingleton<PartyService>();
        serviceCollection.AddSingleton<PartyRegistry>();
        serviceCollection.AddSingleton<ChatHistory>();
        serviceCollection.AddSingleton<RateLimiter>();
        serviceCollection.AddSingleton<PartyHub>();
        serviceCollection.AddHostedService<WatchPartyHostedService>();
        serviceCollection.AddHostedService<NewTitlesHostedService>();
        serviceCollection.AddHostedService<ContactReminderHostedService>();
    }
}
