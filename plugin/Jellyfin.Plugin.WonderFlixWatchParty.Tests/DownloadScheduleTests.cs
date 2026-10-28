using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class DownloadScheduleTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void EverySixHoursInTheFirstWeek() =>
        Assert.Equal(Now.AddHours(6), DownloadSchedule.Next(Now.AddDays(-2), Now));

    [Fact]
    public void DailyUntilThirtyDays() =>
        Assert.Equal(Now.AddHours(24), DownloadSchedule.Next(Now.AddDays(-10), Now));

    [Fact]
    public void WeeklyAfter() =>
        Assert.Equal(Now.AddDays(7), DownloadSchedule.Next(Now.AddDays(-40), Now));

    [Fact]
    public void TheBoundariesGoToTheSlowerPace()
    {
        Assert.Equal(Now.AddHours(24), DownloadSchedule.Next(Now.AddDays(-7), Now));
        Assert.Equal(Now.AddDays(7), DownloadSchedule.Next(Now.AddDays(-30), Now));
    }
}
