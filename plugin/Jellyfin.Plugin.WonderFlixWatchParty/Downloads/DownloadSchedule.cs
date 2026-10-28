namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Quando ricercare di nuovo un titolo che manca, e le soglie di tempo dei download (spec T §3).</summary>
public static class DownloadSchedule
{
    /// <summary>Un titolo senza candidati validi da così tanto passa a "Serve te".</summary>
    public static readonly TimeSpan NeedsYouAfter = TimeSpan.FromDays(7);

    /// <summary>Per questo tempo dopo l'arrivo si tiene d'occhio un titolo per un file migliore.</summary>
    public static readonly TimeSpan UpgradeWindow = TimeSpan.FromDays(30);

    /// <summary>Un download il cui <c>sizeleft</c> non cambia da così tanto è fermo.</summary>
    public static readonly TimeSpan StalledAfter = TimeSpan.FromHours(24);

    /// <summary>Ritmo della prima settimana.</summary>
    private static readonly TimeSpan FirstWeekPace = TimeSpan.FromHours(6);

    /// <summary>Ritmo fino al trentesimo giorno.</summary>
    private static readonly TimeSpan MonthPace = TimeSpan.FromHours(24);

    /// <summary>Ritmo dopo il trentesimo giorno.</summary>
    private static readonly TimeSpan LatePace = TimeSpan.FromDays(7);

    /// <summary>La prossima ricerca: ogni 6 ore sotto i 7 giorni di età, ogni 24 ore sotto i 30, poi ogni 7 giorni. Il limite va al ritmo più lento.</summary>
    public static DateTimeOffset Next(DateTimeOffset since, DateTimeOffset now)
    {
        var age = now - since;
        return now + (age < NeedsYouAfter ? FirstWeekPace : age < UpgradeWindow ? MonthPace : LatePace);
    }
}
