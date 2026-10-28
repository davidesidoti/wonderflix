using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>I dati della regola per un titolo (spec T §4). <c>RuntimeMinutes</c> 0 vuol dire "durata sconosciuta".</summary>
public sealed record RuleInput(int RuntimeMinutes, bool IsMovie, double MinGbPerHour, int MinScore, IReadOnlyDictionary<int, int> IndexerPriority);

/// <summary>Una release scartata. <c>Reason</c>: "Arr" (<c>Detail</c> = il primo rifiuto) o "TooSmall" (<c>Detail</c> = GB all'ora) (spec T §4).</summary>
public sealed record RuleRejected(ArrRelease Release, string Reason, string? Detail);

/// <summary>L'esito della regola: candidati già ordinati, scartati, scelta e se il migliore è sotto il minimo (spec T §4).</summary>
public sealed record RuleResult(IReadOnlyList<ArrRelease> Candidates, IReadOnlyList<RuleRejected> Rejected, ArrRelease? Choice, bool BelowMinScore);

/// <summary>La regola con cui l'admin sceglie la release, e "lo importerebbero?" (spec T §4 e §5).</summary>
public static class DownloadRule
{
    /// <summary>Peso minimo predefinito, in GB all'ora (1 GB = 10^9 byte).</summary>
    public const double DefaultMinGbPerHour = 0.8;

    /// <summary>Durata di un film quando Radarr non la conosce.</summary>
    public const int FallbackMovieMinutes = 100;

    /// <summary>Durata di un episodio quando Sonarr non la conosce.</summary>
    public const int FallbackEpisodeMinutes = 40;

    /// <summary>Priorità di un indexer che Radarr/Sonarr non elencano (il numero più basso è il preferito).</summary>
    private const int UnknownIndexerPriority = 25;

    /// <summary>Rifiuti che non contano: dipendono dal file che c'è già o dalla coda, non dalla release (spec T §4).</summary>
    public static IReadOnlyList<string> IgnoredRejectionPrefixes { get; } =
        ["Existing file on disk", "Not an upgrade", "Release in queue"];

    /// <summary>Applica la regola: scarta, ordina e sceglie (spec T §4).</summary>
    public static RuleResult Choose(IEnumerable<ArrRelease?> releases, RuleInput input)
    {
        var minutes = input.RuntimeMinutes > 0
            ? input.RuntimeMinutes
            : input.IsMovie ? FallbackMovieMinutes : FallbackEpisodeMinutes;

        var candidates = new List<ArrRelease>();
        var rejected = new List<RuleRejected>();
        foreach (var release in releases)
        {
            if (release is null || string.IsNullOrEmpty(release.Guid))
            {
                continue;
            }

            var realRejection = release.Rejections?.FirstOrDefault(text => !IsIgnored(text));
            if (realRejection is not null)
            {
                rejected.Add(new RuleRejected(release, "Arr", realRejection));
                continue;
            }

            var gbPerHour = GbPerHour(release.Size, minutes);
            if (gbPerHour < input.MinGbPerHour)
            {
                rejected.Add(new RuleRejected(release, "TooSmall", gbPerHour.ToString("0.00", CultureInfo.InvariantCulture)));
                continue;
            }

            candidates.Add(release);
        }

        var ordered = candidates
            .OrderByDescending(r => r.CustomFormatScore)
            .ThenByDescending(r => r.Quality?.Quality?.Resolution ?? 0)
            .ThenBy(r => r.Size)
            .ThenByDescending(r => r.Seeders ?? 0)
            .ThenBy(r => input.IndexerPriority.TryGetValue(r.IndexerId, out var p) ? p : UnknownIndexerPriority)
            .ThenBy(r => r.Guid, StringComparer.Ordinal) // ultimo spareggio: l'ordine non dipende da quello della ricerca
            .ToList();

        var best = ordered.Count > 0 ? ordered[0] : null;
        var meetsMinimum = best is not null && best.CustomFormatScore >= input.MinScore;
        return new RuleResult(ordered, rejected, meetsMinimum ? best : null, best is not null && !meetsMinimum);
    }

    /// <summary>
    /// Radarr/Sonarr importerebbero la release nuova al posto del file attuale? Conta la posizione della qualità nel profilo
    /// (un gruppo è una posizione sola): importa se è più alta, o uguale con punteggio più alto (spec T §5).
    /// </summary>
    public static bool WouldImport(ArrQualityProfile profile, int newQualityId, int newScore, int? currentQualityId, int? currentScore)
    {
        var newPosition = PositionOf(profile, newQualityId);
        if (newPosition < 0)
        {
            return false;
        }

        if (currentQualityId is null)
        {
            return true;
        }

        // Un file attuale fuori dal profilo vale -1: qualsiasi qualità ammessa è più in alto.
        var currentPosition = PositionOf(profile, currentQualityId.Value);
        return newPosition > currentPosition || (newPosition == currentPosition && newScore > (currentScore ?? 0));
    }

    /// <summary>GB (10^9 byte) all'ora; 0 se la durata non è positiva.</summary>
    public static double GbPerHour(long sizeBytes, int runtimeMinutes) =>
        runtimeMinutes > 0 ? sizeBytes / 1_000_000_000.0 / (runtimeMinutes / 60.0) : 0;

    private static bool IsIgnored(string? text) =>
        text is not null && IgnoredRejectionPrefixes.Any(p => text.StartsWith(p, StringComparison.OrdinalIgnoreCase));

    /// <summary>Posizione tra le voci ammesse (dal più basso); -1 se la qualità non c'è.</summary>
    private static int PositionOf(ArrQualityProfile profile, int qualityId)
    {
        var position = 0;
        foreach (var item in profile.Items ?? [])
        {
            if (!item.Allowed)
            {
                continue;
            }

            if (item.Quality?.Id == qualityId || (item.Items?.Any(member => member.Quality?.Id == qualityId) ?? false))
            {
                return position;
            }

            position++;
        }

        return -1;
    }
}
