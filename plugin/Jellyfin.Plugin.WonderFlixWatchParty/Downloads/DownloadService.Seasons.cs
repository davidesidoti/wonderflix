using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Il giro, le stagioni intere (spec T §5.4, decisione 6): una stagione finita che manca tutta è una voce sola,
/// cercata come stagione; se il pack non conviene si divide in episodi e non si riunisce più.
/// </summary>
public sealed partial class DownloadService
{
    // Una stagione (> 0) con episodi mancanti, letta fuori dal lock; se diventa una voce lo decide GroupSeasons.
    // Whole: finita (ogni episodio ha una messa in onda passata) e con tutti i monitorati mancanti.
    // EpisodeIds: tutti gli episodi della stagione (vuoto se la serie non si è letta); Missing: i numeri dei mancanti, senza doppioni.
    private sealed record ArrSeason(ArrTitle Title, bool Whole, IReadOnlyList<int> EpisodeIds, IReadOnlyList<ArrTitle> Episodes, IReadOnlyList<int> Missing);

    // Fuori dal lock: gli episodi di ogni serie con episodi mancanti, una lettura per serie e per giro.
    private async Task<Dictionary<string, ArrSeason>> ReadSeasonsAsync(
        IReadOnlyList<SonarrEpisode> missing, IReadOnlyDictionary<string, ArrTitle> titles, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var seasons = new Dictionary<string, ArrSeason>();
        foreach (var series in missing.Where(e => e.SeriesId > 0 && e.SeasonNumber > 0).GroupBy(e => e.SeriesId))
        {
            List<SonarrEpisode>? all = null;
            try
            {
                all = [.. (await arr.GetSeriesEpisodesAsync(series.Key, cancellationToken).ConfigureAwait(false)).OfType<SonarrEpisode>()];
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                // Senza gli episodi non si sa se una stagione è finita: per questo giro restano episodi.
                logger.LogWarning("Download automatici: Sonarr non ha dato gli episodi della serie {SeriesId} ({Error})", series.Key, ErrorOf(ex));
            }

            foreach (var season in series.GroupBy(e => e.SeasonNumber))
            {
                var missingIds = season.Select(e => e.Id).ToHashSet();
                var episodes = all?.Where(e => e.SeasonNumber == season.Key).ToList() ?? [];
                var monitored = episodes.Where(e => e.Monitored).Select(e => e.Id).ToList();

                // Una data che manca non è passata (il confronto con null è falso).
                var whole = episodes.All(e => e.AirDateUtc <= now) && monitored.Count > 0 && monitored.All(missingIds.Contains);
                var episodeTitles = missingIds.Select(id => titles[Key(DownloadKinds.Episode, id)]).ToList();
                var show = season.First().Series;
                var key = new DownloadKey(DownloadKinds.Season, series.Key, season.Key).ToString();
                var title = new ArrTitle(
                    key,
                    DownloadKinds.Season,
                    SeasonTitleOf(show?.Title, season.Key),
                    Poster(show?.Images),
                    show?.QualityProfileId ?? 0,
                    show?.Runtime ?? 0,
                    whole ? episodes.Max(e => e.AirDateUtc) : season.Max(e => e.AirDateUtc),
                    Monitored: true,
                    Followed: true,
                    Wanted: episodeTitles.Any(t => t.Wanted),
                    HasFile: false,
                    SeriesId: series.Key);
                seasons[key] = new ArrSeason(
                    title,
                    whole,
                    [.. episodes.Select(e => e.Id)],
                    episodeTitles,
                    [.. season.Select(e => e.EpisodeNumber).Distinct().Order()]);
            }
        }

        return seasons;
    }

    // La coda di Sonarr per stagione, dall'id più basso: un pack ha un elemento per episodio (o uno senza episodio).
    private static Dictionary<string, IReadOnlyList<ArrQueueItem>> SeasonQueueOf(IEnumerable<ArrQueueItem> records) =>
        records
            .Where(q => q.SeriesId > 0 && q.SeasonNumber > 0)
            .GroupBy(q => new DownloadKey(DownloadKinds.Season, q.SeriesId!.Value, q.SeasonNumber!.Value).ToString())
            .ToDictionary(g => g.Key, g => (IReadOnlyList<ArrQueueItem>)[.. g.OrderBy(q => q.Id)]);

    // Solo sotto _lock. La vista di Sonarr con le stagioni intere al posto dei loro episodi, nei titoli e nella coda.
    private ArrView GroupSeasons(ArrView view, DateTimeOffset now)
    {
        var seasons = view.Seasons ?? new Dictionary<string, ArrSeason>();
        var seasonQueue = view.SeasonQueue ?? new Dictionary<string, IReadOnlyList<ArrQueueItem>>();
        var grouped = Book.Entries.Where(e => e.Kind == DownloadKinds.Season).Select(e => e.Key).ToHashSet();
        var chosen = Book.Choices.Select(c => c.Key).ToHashSet();
        foreach (var season in seasons.Values.Where(s => s.Whole && !grouped.Contains(s.Title.Key)))
        {
            var episodeKeys = season.EpisodeIds.Select(id => Key(DownloadKinds.Episode, id)).ToList();

            // Mai una stagione divisa, in coda, con un episodio che scarica o tiene d'occhio gli upgrade o già scaricato da WonderFlix.
            if (Book.IsSplit(season.Title.Key)
                || seasonQueue.ContainsKey(season.Title.Key)
                || episodeKeys.Any(k => chosen.Contains(k) || Book.Get(k)?.State is DownloadStates.Downloading or DownloadStates.UpgradeWatch))
            {
                continue;
            }

            // Restano solo voci in attesa (Waiting o NeedsYou): lasciano il posto alla stagione.
            foreach (var episodeKey in episodeKeys)
            {
                Book.Remove(episodeKey);
            }

            Create(season.Title, now);
            grouped.Add(season.Title.Key);
            logger.LogInformation("Download automatici: {Key} è una stagione intera", season.Title.Key);
        }

        var titles = view.Titles.ToDictionary();
        var queue = view.Queue.ToDictionary();
        foreach (var key in grouped)
        {
            // Nessun mancante: la stagione non ha titolo, come un episodio che ha il file.
            if (seasons.TryGetValue(key, out var season))
            {
                foreach (var episode in season.Episodes)
                {
                    titles.Remove(episode.Key);
                }

                titles[key] = season.Title;
            }

            if (seasonQueue.TryGetValue(key, out var records))
            {
                foreach (var record in records.Where(r => r.EpisodeId > 0))
                {
                    queue.Remove(Key(DownloadKinds.Episode, record.EpisodeId!.Value));
                }

                queue[key] = PackQueueItem(records);
            }
        }

        return view with { Titles = titles, Queue = queue };
    }

    // Gli elementi di un pack come un download solo: l'id più basso, la somma di sizeleft (che resta uguale solo se resta
    // uguale ognuno); scarica solo se scaricano tutti, ImportBlocked se lo è uno.
    private static ArrQueueItem PackQueueItem(IReadOnlyList<ArrQueueItem> records)
    {
        var downloading = records.All(r =>
            string.Equals(r.Status, DownloadingState, StringComparison.OrdinalIgnoreCase)
            && string.Equals(r.TrackedDownloadState, DownloadingState, StringComparison.OrdinalIgnoreCase));
        var blocked = records.Any(r => string.Equals(r.TrackedDownloadState, ImportBlockedState, StringComparison.OrdinalIgnoreCase));
        return new ArrQueueItem
        {
            Id = records[0].Id,
            SeriesId = records[0].SeriesId,
            SeasonNumber = records[0].SeasonNumber,
            DownloadId = records[0].DownloadId,
            Sizeleft = records.Sum(r => r.Sizeleft),
            Status = downloading ? DownloadingState : null,
            TrackedDownloadState = blocked ? ImportBlockedState : downloading ? DownloadingState : null,
        };
    }

    // Il pack non conviene: la voce di stagione esce e ogni episodio mancante ha la sua, da cercare subito (decisione 6).
    private void Split(SearchItem item)
    {
        lock (_lock)
        {
            if (Book.Get(item.Key) is not { } entry || entry.State == DownloadStates.Downloading)
            {
                return;
            }

            var now = time.GetUtcNow();
            Book.Remove(item.Key);
            Book.Split(item.Key);
            foreach (var episode in item.SplitInto ?? [])
            {
                if (Book.Get(episode.Key) is null)
                {
                    Create(episode, now);
                }
            }
        }

        logger.LogInformation("Download automatici: {Key} diviso in episodi", item.Key);
    }
}
