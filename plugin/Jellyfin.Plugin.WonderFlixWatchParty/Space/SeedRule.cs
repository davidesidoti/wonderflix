namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Quello che serve sapere di un torrent per decidere se si può togliere (spec U §6.3).</summary>
public sealed record TorrentFacts(string Hash, string Name, string TrackerHost, long SizeBytes, double Progress, double Ratio, long SeedingSeconds);

/// <summary>La regola del seed obbligatorio: i domini protetti, il rapporto e i giorni (spec U §6.3).</summary>
public sealed record SeedSettings(IReadOnlyList<string> ProtectedDomains, double Ratio, int Days);

/// <summary>L'esito: si può togliere adesso, oppure da quando (<c>ExpectedAt</c>; null se non si può prevedere) (spec U §6.3).</summary>
public sealed record SeedVerdict(bool CanRemoveNow, DateTimeOffset? ExpectedAt);

/// <summary>La regola del seed obbligatorio dei tracker privati (spec U §6.3).</summary>
public static class SeedRule
{
    /// <summary>Secondi in un giorno.</summary>
    private const int SecondsPerDay = 86_400;

    /// <summary>Un torrent su un tracker protetto si toglie dopo il rapporto o i giorni di seed; gli altri subito. Uno ancora in download non si toglie mai.</summary>
    public static SeedVerdict Check(TorrentFacts torrent, SeedSettings settings, DateTimeOffset now)
    {
        if (torrent.Progress < 1)
        {
            return new SeedVerdict(false, null);
        }

        if (!IsProtected(torrent.TrackerHost, settings.ProtectedDomains))
        {
            return new SeedVerdict(true, null);
        }

        var requiredSeconds = settings.Days * (long)SecondsPerDay;
        if (torrent.Ratio >= settings.Ratio || torrent.SeedingSeconds >= requiredSeconds)
        {
            return new SeedVerdict(true, null);
        }

        return new SeedVerdict(false, now.AddSeconds(requiredSeconds - torrent.SeedingSeconds));
    }

    /// <summary>Vero se l'host è uno dei domini o un suo sottodominio, senza badare alle maiuscole.</summary>
    public static bool IsProtected(string trackerHost, IReadOnlyList<string> domains) =>
        domains.Any(d => !string.IsNullOrWhiteSpace(d)
            && (trackerHost.Equals(d.Trim(), StringComparison.OrdinalIgnoreCase)
                || trackerHost.EndsWith("." + d.Trim(), StringComparison.OrdinalIgnoreCase)));

    /// <summary>L'host (minuscolo) di un URL di announce; vuoto se manca o non è valido.</summary>
    public static string HostOf(string? trackerUrl) =>
        Uri.TryCreate(trackerUrl, UriKind.Absolute, out var uri) ? uri.Host.ToLowerInvariant() : "";
}
