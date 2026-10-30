using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SpaceSignalsTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-30T12:00:00Z");

    private static readonly SpaceThresholds Thresholds = SpaceThresholds.From(new FakeSpaceSettings());

    private static readonly Guid AnnaId = Guid.NewGuid();

    private static readonly Guid LucaId = Guid.NewGuid();

    private static DateTimeOffset Day(string date) => DateTimeOffset.Parse(date + "T12:00:00Z");

    private static UserUsage Anna(bool finished, string? lastPlayed) => new(AnnaId, "Anna", true, finished, lastPlayed is null ? null : Day(lastPlayed));

    private static UserUsage Luca(bool finished, string? lastPlayed) => new(LucaId, "Luca", true, finished, lastPlayed is null ? null : Day(lastPlayed));

    private static TitleFacts Facts(
        IReadOnlyList<UserUsage>? usage = null,
        string? added = null,
        IReadOnlyList<RequestFact>? requests = null,
        double? ratingAvg = null,
        int ratingCount = 0,
        bool sequel = false) =>
        new(added is null ? null : Day(added), usage ?? [], requests ?? [], ratingAvg, ratingCount, sequel);

    private static Signals Eval(TitleFacts facts) => SpaceSignals.Evaluate(facts, Thresholds, Now);

    [Fact]
    public void WatchedLongAgoIsNobodyWatching()
    {
        var s = Eval(Facts([Anna(true, "2026-03-01")]));

        Assert.Equal([SpaceSignalCodes.NobodyWatching], s.Via);
        Assert.Empty(s.Keep);
        Assert.Equal(Day("2026-03-01"), s.LastOpened);
    }

    [Fact]
    public void MixedFinishedAndAbandonedIsNobodyWatching()
    {
        var s = Eval(Facts([Anna(true, "2026-02-01"), Luca(false, "2026-04-01")]));

        Assert.Equal([SpaceSignalCodes.NobodyWatching], s.Via);
        Assert.DoesNotContain(SpaceSignalCodes.InProgress, s.Keep);
        Assert.Equal(Day("2026-04-01"), s.LastOpened);
    }

    [Fact]
    public void RecentlyOpenedIsNotStale()
    {
        var s = Eval(Facts([Luca(false, "2026-10-01")]));

        Assert.Empty(s.Via);
        Assert.Equal([SpaceSignalCodes.InProgress], s.Keep);
    }

    [Fact]
    public void StartedWithoutDateIsNobodyWatching()
    {
        Assert.Equal([SpaceSignalCodes.NobodyWatching], Eval(Facts([Anna(false, null)])).Via);
    }

    [Fact]
    public void NeverOpenedAfterSixMonths()
    {
        Assert.Equal([SpaceSignalCodes.NeverOpened], Eval(Facts(added: "2026-04-01")).Via);
        Assert.Empty(Eval(Facts(added: "2026-06-01")).Via);
        Assert.Empty(Eval(Facts()).Via);
    }

    [Fact]
    public void LowRatingNeedsTwoVotes()
    {
        Assert.Empty(Eval(Facts(ratingAvg: 1.5, ratingCount: 1)).Via);
        Assert.Equal([SpaceSignalCodes.LowRating], Eval(Facts(ratingAvg: 1.5, ratingCount: 2)).Via);
        Assert.Empty(Eval(Facts(ratingAvg: null, ratingCount: 5)).Via);
    }

    [Fact]
    public void HighRatingKeeps()
    {
        Assert.Empty(Eval(Facts(ratingAvg: 4.5, ratingCount: 1)).Keep);
        Assert.Equal([SpaceSignalCodes.HighRating], Eval(Facts(ratingAvg: 4.0, ratingCount: 2)).Keep);
    }

    [Fact]
    public void ARecentRequestNotWatchedKeeps()
    {
        var req = new[] { new RequestFact(AnnaId, "Anna", Day("2026-10-01")) };

        Assert.Contains(SpaceSignalCodes.RecentRequest, Eval(Facts(requests: req)).Keep);
        Assert.Contains(SpaceSignalCodes.RecentRequest, Eval(Facts([Anna(false, "2026-10-02")], requests: req)).Keep);
        Assert.DoesNotContain(SpaceSignalCodes.RecentRequest, Eval(Facts([Anna(true, "2026-10-05")], requests: req)).Keep);
        Assert.DoesNotContain(
            SpaceSignalCodes.RecentRequest,
            Eval(Facts(requests: [new RequestFact(AnnaId, "Anna", Day("2026-07-01"))])).Keep);
        Assert.Contains(
            SpaceSignalCodes.RecentRequest,
            Eval(Facts(requests: [new RequestFact(null, "Admin", Day("2026-10-01"))])).Keep);
    }

    [Fact]
    public void SequelComingKeeps()
    {
        Assert.Contains(SpaceSignalCodes.SequelComing, Eval(Facts(sequel: true)).Keep);
    }

    [Fact]
    public void ListsFollowConstantOrderWithoutDuplicates()
    {
        var s = Eval(Facts(
            [Anna(false, "2026-10-01"), Luca(true, "2026-01-01")],
            added: "2026-01-01",
            requests: [new RequestFact(null, "A", Day("2026-10-01")), new RequestFact(null, "B", Day("2026-10-02"))],
            ratingAvg: 4.5,
            ratingCount: 3,
            sequel: true));

        Assert.Equal(
            [SpaceSignalCodes.InProgress, SpaceSignalCodes.RecentRequest, SpaceSignalCodes.HighRating, SpaceSignalCodes.SequelComing],
            s.Keep);
    }
}
