using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
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
        // Home su misura (spec M): la Home dell'admin e le uscite di Sonarr e Radarr.
        serviceCollection.AddSingleton<IHomeLayoutStore, PluginHomeLayoutStore>();
        serviceCollection.AddSingleton<IArrSettings, PluginArrSettings>();
        // La chiave API non va nei log del client HTTP e non segue un redirect.
        serviceCollection.AddHttpClient(ArrClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false })
            .RedactLoggedHeaders(["X-Api-Key"]);
        serviceCollection.AddSingleton<IArrClient, ArrClient>();
        // Spazio (spec U): qBittorrent. Il cookie SID lo gestisce il client: niente CookieContainer, niente redirect,
        // e Cookie/Set-Cookie non vanno nei log del client HTTP.
        serviceCollection.AddSingleton<ISpaceSettings, PluginSpaceSettings>();
        serviceCollection.AddHttpClient(QbitClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false })
            .RedactLoggedHeaders(["Cookie", "Set-Cookie"]);
        serviceCollection.AddSingleton<IQbitClient, QbitClient>();
        serviceCollection.AddSingleton<IFileProbe, LinuxFileProbe>();
        serviceCollection.AddSingleton<IViewingFacts, JellyfinViewingFacts>();
        serviceCollection.AddSingleton<ILibraryRefresh, JellyfinLibraryRefresh>();
        serviceCollection.AddSingleton<ISeriesIndex, JellyfinSeriesIndex>();
        serviceCollection.AddSingleton<UpcomingService>();
        serviceCollection.AddSingleton<ReleaseDatesService>();
        serviceCollection.AddSingleton<CalendarService>();
        serviceCollection.AddSingleton<ILibraryTitles, JellyfinLibraryTitles>();
        // Consigli tra amici (spec N).
        serviceCollection.AddSingleton(provider => new RecommendationStore(
            RecommendationStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<RecommendationStore>>()));
        serviceCollection.AddSingleton<IRecommendationLibrary, JellyfinRecommendationLibrary>();
        serviceCollection.AddSingleton<RecommendationService>();
        // Cosa guardano gli amici (spec O).
        serviceCollection.AddSingleton(provider => new ActivityStore(
            ActivityStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ActivityStore>>()));
        serviceCollection.AddSingleton<IPlaybackDirectory, JellyfinPlaybackDirectory>();
        serviceCollection.AddSingleton<ActivityService>();
        // Match del film (spec P).
        serviceCollection.AddSingleton<IMatchLibrary, JellyfinMatchLibrary>();
        serviceCollection.AddSingleton<MatchStackBuilder>();
        serviceCollection.AddSingleton<MatchService>();
        // Voti degli amici (spec Q).
        serviceCollection.AddSingleton(provider => new RatingStore(
            RatingStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<RatingStore>>()));
        serviceCollection.AddSingleton<IRatingLibrary, JellyfinRatingLibrary>();
        serviceCollection.AddSingleton<RatingService>();
        serviceCollection.AddSingleton<RatingRoundService>();
        // Segnalazioni e sottotitoli (spec R).
        serviceCollection.AddSingleton(provider => new ReportStore(
            ReportStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ReportStore>>()));
        serviceCollection.AddSingleton<IReportLibrary, JellyfinReportLibrary>();
        serviceCollection.AddSingleton<ReportService>();
        serviceCollection.AddSingleton<ISubtitleTools, JellyfinSubtitleTools>();
        serviceCollection.AddSingleton<SubtitleService>();
        // Download automatici (spec T).
        serviceCollection.AddSingleton(provider => new DownloadStore(
            DownloadStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<DownloadStore>>()));
        serviceCollection.AddSingleton<IDownloadSettings, PluginDownloadSettings>();
        serviceCollection.AddSingleton<DownloadService>();
        serviceCollection.AddSingleton(provider => new SpaceStore(
            SpaceStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<SpaceStore>>()));
        serviceCollection.AddSingleton<SpaceService>();
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
        serviceCollection.AddHostedService<RecommendationsHostedService>();
        serviceCollection.AddHostedService<ActivityHostedService>();
        serviceCollection.AddHostedService<MatchHostedService>();
        serviceCollection.AddHostedService<RatingsHostedService>();
        serviceCollection.AddHostedService<ReportsHostedService>();
        serviceCollection.AddHostedService<DownloadsHostedService>();
        serviceCollection.AddHostedService<SpaceHostedService>();
    }
}
