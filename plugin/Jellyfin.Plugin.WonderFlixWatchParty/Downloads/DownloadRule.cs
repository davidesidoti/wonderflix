using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// I dati della regola per un titolo (spec T §4). <c>RuntimeMinutes</c> 0 vuol dire "durata sconosciuta". <c>EpisodeMinutes</c>:
/// per la regola di una stagione la durata di un episodio, così il peso di un pack completo si misura su tutta la stagione.
/// </summary>
public sealed record RuleInput(int RuntimeMinutes, bool IsMovie, double MinGbPerHour, int MinScore, IReadOnlyDictionary<int, int> IndexerPriority, ChecksContext? Checks = null, int EpisodeMinutes = 0);

/// <summary>
/// Una release scartata. <c>Reason</c>: "Arr" (<c>Detail</c> = il primo rifiuto), "TooSmall" (<c>Detail</c> = GB all'ora) (spec T §4),
/// o, per Prowlarr, "Blocklisted", "Restricted" (<c>Detail</c> = il termine), "NotWanted" (<c>Detail</c> = qualità, "Size", "Seeders" o "Score").
/// </summary>
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

            if (input.Checks is { } checks && release.Source == ReleaseSource.Prowlarr
                && ReleaseChecks.Check(release, checks, input.RuntimeMinutes, SeasonMinutesOf(release, input)) is var (reason, detail))
            {
                rejected.Add(new RuleRejected(release, reason, detail));
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

    // Un pack completo copre tutti gli episodi della stagione: il parse di Sonarr li elenca tutti, non solo i mancanti.
    private static int? SeasonMinutesOf(ArrRelease release, RuleInput input) =>
        release.FullSeason && input.EpisodeMinutes > 0 && release.SeasonEpisodeNumbers is { Count: > 0 } episodes
            ? input.EpisodeMinutes * episodes.Count
            : null;

    /// <summary>
    /// Radarr/Sonarr importerebbero la release nuova al posto del file attuale? Conta la posizione della qualità tra TUTTE
    /// le voci del profilo, ammesse o no, come fa Sonarr (un gruppo è una posizione sola): importa se è più alta, o uguale con
    /// punteggio più alto. La qualità nuova deve essere ammessa; un file attuale fuori dal profilo vale -1 (spec T §5).
    /// </summary>
    public static bool WouldImport(ArrQualityProfile profile, int newQualityId, int newScore, int? currentQualityId, int? currentScore)
    {
        if (!IsAllowed(profile, newQualityId))
        {
            return false;
        }

        var newPosition = PositionOf(profile, newQualityId);

        if (currentQualityId is null)
        {
            return true;
        }

        // Un file attuale fuori dal profilo vale -1: qualsiasi qualità ammessa è più in alto. Una non ammessa conta (Spider-Noir).
        var currentPosition = PositionOf(profile, currentQualityId.Value);
        return newPosition > currentPosition || (newPosition == currentPosition && newScore > (currentScore ?? 0));
    }

    /// <summary>La qualità è nel profilo e ammessa (una dentro un gruppo ammesso lo è).</summary>
    public static bool IsAllowed(ArrQualityProfile profile, int qualityId)
    {
        var position = PositionOf(profile, qualityId);
        return position >= 0 && profile.Items![position].Allowed;
    }

    /// <summary>Il formato in cui una release si ricorda tra una ricerca e l'altra: <c>indexerId|guid</c>.</summary>
    public static string ReleaseId(string guid, int indexerId) => $"{indexerId}|{guid}";

    /// <summary>
    /// Il tappabuchi quando non c'è una scelta: il migliore sotto il minimo di punteggio, oppure tra i troppo piccoli quello
    /// più pesante (a parità di punteggio e risoluzione). I rifiutati da Arr non si scelgono mai.
    /// </summary>
    public static (ArrRelease? Release, string? Kind) ChooseStopgap(RuleResult rule)
    {
        if (rule.BelowMinScore)
        {
            return (rule.Candidates[0], DownloadStopgaps.Score);
        }

        var heaviest = rule.Rejected
            .Where(r => r.Reason == "TooSmall")
            .Select(r => r.Release)
            .OrderByDescending(r => r.CustomFormatScore)
            .ThenByDescending(r => r.Quality?.Quality?.Resolution ?? 0)
            .ThenByDescending(r => r.Size)
            .ThenByDescending(r => r.Seeders ?? 0)
            .ThenBy(r => r.Guid, StringComparer.Ordinal)
            .FirstOrDefault();
        return heaviest is null ? (null, null) : (heaviest, DownloadStopgaps.Size);
    }

    /// <summary>Che tappabuchi sarebbe una release: "Size" se è troppo piccola, "Score" se pesa abbastanza ma è sotto il minimo, null se la regola la accetta.</summary>
    public static string? StopgapKindOf(int score, long sizeBytes, int runtimeMinutes, bool isMovie, double minGbPerHour, int minScore)
    {
        var minutes = runtimeMinutes > 0 ? runtimeMinutes : isMovie ? FallbackMovieMinutes : FallbackEpisodeMinutes;
        if (GbPerHour(sizeBytes, minutes) < minGbPerHour)
        {
            return DownloadStopgaps.Size;
        }

        return score < minScore ? DownloadStopgaps.Score : null;
    }

    /// <summary>Il riassunto di una ricerca: quante release, quante scartate e perché, e se c'è un tappabuchi.</summary>
    public static DownloadSummary Summarize(RuleResult rule, int found, int minScore)
    {
        var arr = rule.Rejected.Where(r => r.Reason == "Arr").ToList();
        var tooSmall = rule.Rejected.Count(r => r.Reason == "TooSmall");
        return new DownloadSummary
        {
            Found = found,
            BestScore = rule.Candidates.Count > 0 ? rule.Candidates[0].CustomFormatScore : null,
            MinScore = minScore,
            TooSmall = tooSmall,
            ArrRejected = arr.Count,
            // GroupBy tiene l'ordine di comparsa e OrderBy è stabile: a parità vince il primo incontrato.
            TopRejection = arr.Where(r => r.Detail is not null).GroupBy(r => r.Detail).OrderByDescending(g => g.Count()).Select(g => g.Key).FirstOrDefault(),
            StopgapAvailable = ChooseStopgap(rule).Release is not null,
        };
    }

    /// <summary>GB (10^9 byte) all'ora; 0 se la durata non è positiva.</summary>
    public static double GbPerHour(long sizeBytes, int runtimeMinutes) =>
        runtimeMinutes > 0 ? sizeBytes / 1_000_000_000.0 / (runtimeMinutes / 60.0) : 0;

    private static bool IsIgnored(string? text) =>
        text is not null && IgnoredRejectionPrefixes.Any(p => text.StartsWith(p, StringComparison.OrdinalIgnoreCase));

    /// <summary>Posizione tra tutte le voci, ammesse o no (dal più basso); -1 se la qualità non c'è.</summary>
    private static int PositionOf(ArrQualityProfile profile, int qualityId) =>
        profile.Items?.FindIndex(item => item.Quality?.Id == qualityId || (item.Items?.Any(member => member.Quality?.Id == qualityId) ?? false)) ?? -1;
}
