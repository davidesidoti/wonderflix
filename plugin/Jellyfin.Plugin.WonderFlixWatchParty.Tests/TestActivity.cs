using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>L'attività dei test: server finto, amici e presenza veri, file in una cartella temporanea.</summary>
internal static class TestActivity
{
    public static ActivityService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, PresenceTracker presence,
        PartyRegistry? registry = null) =>
        new(
            new ActivityStore(folder.ActivityFile, NullLogger<ActivityStore>.Instance),
            friends, server, server, server, registry ?? new PartyRegistry(), server, server, presence, time,
            NullLogger<ActivityService>.Instance);

    /// <summary>Le visioni salvate di un utente, rilette dal file.</summary>
    public static IReadOnlyList<WatchedTitle> Saved(TempFolder folder, Guid userId) =>
        new ActivityStore(folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load().Views(userId);

    // Senza checkIn il resoconto è "appena arrivato" (un'ora nel futuro del tempo finto, sempre recente).
    public static PlaybackReport Report(
        CallerSession session, Guid? titleId, TimeSpan position, bool completed = false, DateTimeOffset? checkIn = null) =>
        new(session.SessionId, session.UserId, titleId, position.Ticks, completed, checkIn ?? DateTimeOffset.MaxValue);

    public static AppPlayback Movie(
        CallerSession session, Guid movieId, string name = "Dune", TimeSpan position = default, DateTimeOffset checkIn = default) =>
        new(session.SessionId, session.UserId, new PlayingTitle(movieId, name, movieId, null, null, null, null), position.Ticks, checkIn);
}
