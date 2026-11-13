using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Pack di stagione o episodi singoli (spec T §5.4).</summary>
public static class SeasonPackRule
{
    /// <summary>Il pack si prende se pesa al massimo così tante volte la somma dei singoli scelti.</summary>
    public const double MaxPackRatio = 1.2;

    /// <summary>
    /// La release del pack da scaricare, o null per dividere la stagione in episodi. Il pack si sceglie con la regola
    /// sulla durata di tutti gli episodi mancanti; si prende se a un episodio manca un singolo valido o se non pesa troppo più dei singoli.
    /// </summary>
    public static ArrRelease? ChoosePack(IEnumerable<ArrRelease?> releases, IReadOnlyCollection<int> missingEpisodes, RuleInput perEpisode) =>
        PackCandidates(releases, missingEpisodes, perEpisode).FirstOrDefault();

    /// <summary>
    /// I pack da provare in ordine di regola: vuoto se il primo (la scelta di <see cref="ChoosePack"/>) non si prende; gli altri
    /// con lo stesso limite sul peso dei singoli.
    /// </summary>
    public static IReadOnlyList<ArrRelease> PackCandidates(IEnumerable<ArrRelease?> releases, IReadOnlyCollection<int> missingEpisodes, RuleInput perEpisode)
    {
        if (missingEpisodes.Count == 0)
        {
            return [];
        }

        var all = releases.OfType<ArrRelease>().ToList();
        var packs = Packs(all, missingEpisodes.Count, perEpisode);
        if (packs.Choice is null)
        {
            return [];
        }

        // Senza un singolo valido per ogni episodio nessun limite: il pack è l'unico modo di avere tutta la stagione.
        var singles = all.Where(r => !r.FullSeason && r.SeasonEpisodeNumbers is { Count: 1 }).ToLookup(r => r.SeasonEpisodeNumbers![0]);
        long sum = 0;
        foreach (var episode in missingEpisodes)
        {
            var single = DownloadRule.Choose(singles[episode], perEpisode).Choice;
            if (single is null)
            {
                return packs.Candidates;
            }

            sum += single.Size;
        }

        return packs.Choice.Size <= MaxPackRatio * sum ? [.. packs.Candidates.Where(p => p.Size <= MaxPackRatio * sum)] : [];
    }

    /// <summary>
    /// Il risultato dei pack se la stagione non ha niente in una qualità ammessa (né pack né singoli, nemmeno troppo leggeri
    /// o sotto punteggio) e il tappabuchi dei pack è un 720p scartato solo per la qualità; altrimenti null.
    /// </summary>
    public static RuleResult? QualityPack(IEnumerable<ArrRelease?> releases, IReadOnlyCollection<int> missingEpisodes, RuleInput perEpisode)
    {
        if (missingEpisodes.Count == 0)
        {
            return null;
        }

        var all = releases.OfType<ArrRelease>().ToList();
        var packs = Packs(all, missingEpisodes.Count, perEpisode);
        var singles = DownloadRule.Choose(all.Where(r => !r.FullSeason && r.SeasonEpisodeNumbers is { Count: 1 }), perEpisode);
        return HasAllowedQuality(packs) || HasAllowedQuality(singles) || DownloadRule.ChooseStopgap(packs).Kind != DownloadStopgaps.Quality
            ? null
            : packs;
    }

    // Una release con qualità ammessa è o candidata o scartata per altro (peso): le sole scartate per qualità non contano.
    private static bool HasAllowedQuality(RuleResult result) =>
        result.Candidates.Count > 0 || result.Rejected.Any(r => r.Reason == "TooSmall");

    /// <summary>La regola sui soli pack completi, sulla durata di <paramref name="missingCount"/> episodi: i candidati sono i pack validi in ordine.</summary>
    public static RuleResult Packs(IEnumerable<ArrRelease?> releases, int missingCount, RuleInput perEpisode)
    {
        var episodeMinutes = perEpisode.RuntimeMinutes > 0 ? perEpisode.RuntimeMinutes : DownloadRule.FallbackEpisodeMinutes;
        return DownloadRule.Choose(releases.Where(r => r?.FullSeason == true), perEpisode with { RuntimeMinutes = episodeMinutes * missingCount, EpisodeMinutes = episodeMinutes });
    }
}
