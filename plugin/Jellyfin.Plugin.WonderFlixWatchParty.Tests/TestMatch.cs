using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il match dei test: server finto, amici e cassetta veri, file in una cartella temporanea.</summary>
internal static class TestMatch
{
    public static MatchService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, PartyDirectory? parties = null) =>
        new(
            new MatchStackBuilder(server, server, server, NullLogger<MatchStackBuilder>.Instance),
            friends,
            server,
            server,
            server,
            TestInbox.Create(server, folder, time),
            parties ?? new PartyDirectory(time),
            new RateLimiter(time),
            time,
            NullLogger<MatchService>.Instance);
}
