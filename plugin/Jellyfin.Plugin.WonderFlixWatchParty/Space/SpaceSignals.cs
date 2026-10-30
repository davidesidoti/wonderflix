namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Cosa fa un utente con un titolo: ha iniziato, ha finito, l'ultima volta (spec U §4).</summary>
public sealed record UserUsage(Guid UserId, string Name, bool Started, bool Finished, DateTimeOffset? LastPlayed);

/// <summary>Una richiesta Seerr del titolo; <c>UserId</c> è null se il richiedente non è un utente Jellyfin (spec U §4.2).</summary>
public sealed record RequestFact(Guid? UserId, string Name, DateTimeOffset At);

/// <summary>I fatti di un titolo da cui nascono i segnali (spec U §4).</summary>
public sealed record TitleFacts(
    DateTimeOffset? Added,
    IReadOnlyList<UserUsage> Usage,
    IReadOnlyList<RequestFact> Requests,
    double? RatingAvg,
    int RatingCount,
    bool SequelComing);

/// <summary>Le soglie dei segnali (spec U §4.3).</summary>
public sealed record SpaceThresholds(int StaleMonths, int RequestGraceDays, int LowRating, int HighRating, int MinRatings)
{
    /// <summary>Legge le soglie dalle impostazioni.</summary>
    public static SpaceThresholds From(ISpaceSettings settings) =>
        new(settings.StaleMonths, settings.RequestGraceDays, settings.LowRating, settings.HighRating, settings.MinRatings);
}

/// <summary>I segnali di un titolo: perché toglierlo, perché tenerlo, l'ultima apertura (spec U §4).</summary>
public sealed record Signals(IReadOnlyList<string> Via, IReadOnlyList<string> Keep, DateTimeOffset? LastOpened);

/// <summary>I codici dei segnali, gli stessi valori che escono dall'API (spec U §4.1 e §4.2).</summary>
public static class SpaceSignalCodes
{
    /// <summary>Via: chi l'ha aperto non lo guarda da tempo.</summary>
    public const string NobodyWatching = "NobodyWatching";

    /// <summary>Via: nessuno l'ha mai aperto, da molto.</summary>
    public const string NeverOpened = "NeverOpened";

    /// <summary>Via: voto medio basso.</summary>
    public const string LowRating = "LowRating";

    /// <summary>Tienilo: qualcuno lo sta guardando.</summary>
    public const string InProgress = "InProgress";

    /// <summary>Tienilo: una richiesta recente non ancora vista.</summary>
    public const string RecentRequest = "RecentRequest";

    /// <summary>Tienilo: voto medio alto.</summary>
    public const string HighRating = "HighRating";

    /// <summary>Tienilo: un seguito sta arrivando.</summary>
    public const string SequelComing = "SequelComing";
}

/// <summary>Calcola i segnali "via" e "tienilo" di un titolo (spec U §4).</summary>
public static class SpaceSignals
{
    /// <summary>Valuta un titolo; le liste seguono l'ordine delle costanti, senza doppioni.</summary>
    public static Signals Evaluate(TitleFacts facts, SpaceThresholds t, DateTimeOffset now)
    {
        var stale = now.AddMonths(-t.StaleMonths);
        var started = facts.Usage.Where(u => u.Started).ToList();
        var lastOpened = started.Max(u => u.LastPlayed);
        var rated = facts.RatingAvg is not null && facts.RatingCount >= t.MinRatings;
        var finished = facts.Usage.Where(u => u.Finished).Select(u => u.UserId).ToHashSet();
        var requestFrom = now.AddDays(-t.RequestGraceDays);

        var via = new List<string>();
        if (started.Count > 0 && (lastOpened is null || lastOpened <= stale))
        {
            via.Add(SpaceSignalCodes.NobodyWatching);
        }

        if (started.Count == 0 && facts.Added is { } added && added <= stale)
        {
            via.Add(SpaceSignalCodes.NeverOpened);
        }

        if (rated && facts.RatingAvg <= t.LowRating)
        {
            via.Add(SpaceSignalCodes.LowRating);
        }

        var keep = new List<string>();
        if (started.Any(u => !u.Finished && u.LastPlayed > stale))
        {
            keep.Add(SpaceSignalCodes.InProgress);
        }

        if (facts.Requests.Any(r => r.At > requestFrom && (r.UserId is not { } id || !finished.Contains(id))))
        {
            keep.Add(SpaceSignalCodes.RecentRequest);
        }

        if (rated && facts.RatingAvg >= t.HighRating)
        {
            keep.Add(SpaceSignalCodes.HighRating);
        }

        if (facts.SequelComing)
        {
            keep.Add(SpaceSignalCodes.SequelComing);
        }

        return new Signals(via, keep, lastOpened);
    }
}
