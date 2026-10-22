using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseRulesTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 22, 12, 0, 0, TimeSpan.Zero);

    private static DateTimeOffset? D(int y, int m, int d) => new DateTimeOffset(y, m, d, 0, 0, 0, TimeSpan.Zero);

    public static TheoryData<MovieDates?, bool> Cases => new()
    {
        { null, false },
        { new MovieDates(null, D(2026, 11, 12), null, false), true },
        { new MovieDates(null, D(2026, 10, 20), null, false), false },
        { new MovieDates(null, D(2026, 11, 12), null, true), false },
        { new MovieDates(D(2026, 9, 25), null, null, false), true },
        { new MovieDates(D(2026, 12, 18), null, null, false), true },
        { new MovieDates(D(2024, 10, 1), null, null, false), false },
        { new MovieDates(null, null, null, false), true },
        { new MovieDates(D(2026, 9, 25), null, D(2026, 10, 1), false), false },
    };

    [Theory]
    [MemberData(nameof(Cases))]
    public void AwaitingReleaseRules(MovieDates? dates, bool expected) =>
        Assert.Equal(expected, ReleaseRules.IsAwaitingRelease(dates, Now));
}
