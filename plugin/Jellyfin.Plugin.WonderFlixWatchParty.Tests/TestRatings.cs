using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I voti dei test: server finto, file in una cartella temporanea.</summary>
internal static class TestRatings
{
    public static RatingService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, ILogger<RatingService>? logger = null) =>
        new(
            new RatingStore(folder.RatingsFile, NullLogger<RatingStore>.Instance),
            friends, server, server, server, server,
            new RateLimiter(time), time, logger ?? NullLogger<RatingService>.Instance);

    public static RatingRoundService Rounds(FakeServer server, RatingService ratings, TimeProvider time, PartyDirectory? parties = null) =>
        new(
            ratings, server, server, server, server, server,
            parties ?? new PartyDirectory(time), server, time, NullLogger<RatingRoundService>.Instance);
}
