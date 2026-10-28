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
    public static ArrRelease? ChoosePack(IEnumerable<ArrRelease?> releases, IReadOnlyCollection<int> missingEpisodes, RuleInput perEpisode)
    {
        if (missingEpisodes.Count == 0)
        {
            return null;
        }

        var all = releases.OfType<ArrRelease>().ToList();
        var episodeMinutes = perEpisode.RuntimeMinutes > 0 ? perEpisode.RuntimeMinutes : DownloadRule.FallbackEpisodeMinutes;
        var pack = DownloadRule.Choose(all.Where(r => r.FullSeason), perEpisode with { RuntimeMinutes = episodeMinutes * missingEpisodes.Count }).Choice;
        if (pack is null)
        {
            return null;
        }

        var singles = all.Where(r => !r.FullSeason && r.EpisodeNumbers is { Count: 1 }).ToLookup(r => r.EpisodeNumbers![0]);
        long sum = 0;
        foreach (var episode in missingEpisodes)
        {
            var single = DownloadRule.Choose(singles[episode], perEpisode).Choice;
            if (single is null)
            {
                return pack;
            }

            sum += single.Size;
        }

        return pack.Size <= MaxPackRatio * sum ? pack : null;
    }
}
