using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.Subtitles;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Model.IO;
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
        services.AddSingleton(InterfaceStub<IUserDataManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<ICollectionManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IImageProcessor>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IAuthorizationContext>.Create().Proxy);
        services.AddSingleton(InterfaceStub<ISubtitleManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IProviderManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IFileSystem>.Create().Proxy);
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

        // Home su misura (spec M).
        Assert.IsType<Server.PluginHomeLayoutStore>(provider.GetRequiredService<Home.IHomeLayoutStore>());
        Assert.IsType<Server.PluginArrSettings>(provider.GetRequiredService<Home.IArrSettings>());
        Assert.IsType<Home.ArrClient>(provider.GetRequiredService<Home.IArrClient>());
        Assert.IsType<Server.JellyfinSeriesIndex>(provider.GetRequiredService<Home.ISeriesIndex>());
        Assert.Same(provider.GetRequiredService<Home.UpcomingService>(), provider.GetRequiredService<Home.UpcomingService>());

        // I controller della Home e Info si costruiscono dal DI: InfoController ora vuole anche IArrSettings.
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.InfoController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.HomeController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.UpcomingController>(provider));

        // Consigli tra amici (spec N).
        Assert.Same(provider.GetRequiredService<RecommendationService>(), provider.GetRequiredService<RecommendationService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "recommendations.json"),
            provider.GetRequiredService<RecommendationStore>().FilePath);
        Assert.IsType<Server.JellyfinRecommendationLibrary>(provider.GetRequiredService<IRecommendationLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RecommendationsController>(provider));

        // Cosa guardano gli amici (spec O).
        Assert.Same(provider.GetRequiredService<ActivityService>(), provider.GetRequiredService<ActivityService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "activity.json"),
            provider.GetRequiredService<ActivityStore>().FilePath);
        Assert.IsType<Server.JellyfinPlaybackDirectory>(provider.GetRequiredService<IPlaybackDirectory>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.ActivityController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.FriendsController>(provider));

        // Match del film (spec P).
        Assert.Same(provider.GetRequiredService<MatchService>(), provider.GetRequiredService<MatchService>());
        Assert.NotNull(provider.GetRequiredService<MatchStackBuilder>());
        Assert.IsType<Server.JellyfinMatchLibrary>(provider.GetRequiredService<IMatchLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.MatchController>(provider));

        // Voti degli amici (spec Q).
        Assert.Same(provider.GetRequiredService<RatingService>(), provider.GetRequiredService<RatingService>());
        Assert.Same(provider.GetRequiredService<RatingRoundService>(), provider.GetRequiredService<RatingRoundService>());
        Assert.IsType<Server.JellyfinRatingLibrary>(provider.GetRequiredService<IRatingLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RatingsController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RatingsAdminController>(provider));

        // Segnalazioni e sottotitoli (spec R).
        Assert.Same(provider.GetRequiredService<ReportService>(), provider.GetRequiredService<ReportService>());
        Assert.Same(provider.GetRequiredService<SubtitleService>(), provider.GetRequiredService<SubtitleService>());
        Assert.IsType<Server.JellyfinReportLibrary>(provider.GetRequiredService<IReportLibrary>());
        Assert.IsType<Server.JellyfinSubtitleTools>(provider.GetRequiredService<ISubtitleTools>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.ReportsController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.SubtitlesController>(provider));

        // Calendario delle uscite e date delle richieste (spec S).
        Assert.Same(provider.GetRequiredService<Home.CalendarService>(), provider.GetRequiredService<Home.CalendarService>());
        Assert.Same(provider.GetRequiredService<Home.ReleaseDatesService>(), provider.GetRequiredService<Home.ReleaseDatesService>());

        // Download automatici (spec T).
        Assert.Same(provider.GetRequiredService<Downloads.DownloadService>(), provider.GetRequiredService<Downloads.DownloadService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "downloads.json"),
            provider.GetRequiredService<Downloads.DownloadStore>().FilePath);
        Assert.IsType<Server.PluginDownloadSettings>(provider.GetRequiredService<Downloads.IDownloadSettings>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.DownloadsController>(provider));

        // Il promemoria dei contatti, oltre ai due di prima.
        // I consigli (spec N), oltre ai tre di prima.
        // L'attività degli amici (spec O), oltre ai quattro di prima.
        // Le sale del match (spec P), oltre ai cinque di prima.
        // I voti degli amici (spec Q), oltre ai sei di prima.
        // Le segnalazioni (spec R), oltre ai sette di prima.
        // I download automatici (spec T), oltre agli otto di prima.
        Assert.Equal(9, provider.GetServices<IHostedService>().Count());
    }
}
