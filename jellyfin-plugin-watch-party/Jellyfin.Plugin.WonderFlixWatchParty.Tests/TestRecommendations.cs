using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I consigli dei test: server finto, amici e cassetta veri, file in una cartella temporanea.</summary>
internal static class TestRecommendations
{
    public static FriendService Friends(FakeServer server, TempFolder folder, TimeProvider time) =>
        new(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);

    public static RecommendationService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, InboxService? inbox = null) =>
        new(
            new RecommendationStore(folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance),
            friends, server, server, server, server,
            inbox ?? TestInbox.Create(server, folder, time),
            new RateLimiter(time), time, NullLogger<RecommendationService>.Instance);

    /// <summary>
    /// a e b diventano amici: a chiede, b accetta. Le richieste hanno un
    /// limite per chi chiede (20 all'ora) e vanno solo verso utenti attivi:
    /// per dare tanti amici a uno, o un amico disabilitato, chiede l'altro.
    /// </summary>
    public static async Task MakeFriendsAsync(FriendService friends, Guid a, Guid b)
    {
        await friends.RequestAsync(a, b);
        await friends.AcceptAsync(b, a);
    }
}
