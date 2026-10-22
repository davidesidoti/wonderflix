namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Le date di uscita di un film in Radarr (spec S §6.2).</summary>
public sealed record MovieDates(
    DateTimeOffset? InCinemas, DateTimeOffset? DigitalRelease, DateTimeOffset? PhysicalRelease, bool HasFile);

/// <summary>Il prossimo episodio di una serie in Sonarr (spec S §6.2); i numeri sono null se non si leggono.</summary>
public sealed record SeriesNext(DateTimeOffset NextAiring, int? SeasonNumber, int? EpisodeNumber);

/// <summary>La regola dello stato <c>AwaitingRelease</c> di una richiesta (spec S §6.2).</summary>
public static class ReleaseRules
{
    /// <summary>Un film uscito al cinema da meno di così può ancora arrivare in digitale (spec: ultimi 12 mesi).</summary>
    public static readonly TimeSpan RecentCinemaWindow = TimeSpan.FromDays(365);

    /// <summary>Senza le date (<c>null</c>) non si sa: falso.</summary>
    public static bool IsAwaitingRelease(MovieDates? dates, DateTimeOffset now)
    {
        if (dates is null || dates.HasFile)
        {
            return false;
        }

        if (dates.DigitalRelease is { } digital)
        {
            return digital > now;
        }

        return (dates.PhysicalRelease is null || dates.PhysicalRelease > now)
            && (dates.InCinemas is null || dates.InCinemas > now - RecentCinemaWindow);
    }
}
