using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Esito di un download scelto dall'admin (spec T §8.2): Invalid per una chiave o una release non valide, Expired se la
/// release non c'è più nemmeno in una nuova ricerca, Unavailable se Radarr/Sonarr non rispondono (ruling 7), Busy se
/// un download dello stesso titolo è già in corso, dal giro o da un altro admin (ruling 8), Refused se Radarr/Sonarr
/// hanno risposto con un errore, per esempio il client di download ha rifiutato il torrent (spec T §8.2).
/// </summary>
public enum GrabOutcome
{
    Ok,
    Invalid,
    Expired,
    Unavailable,
    Busy,
    Refused,
}

/// <summary>
/// Le azioni dell'admin (spec T §7.4, §8): la ricerca con la regola, "scarica" e "cambia", "va bene così",
/// "cerca adesso", la panoramica e i profili. Le letture di Radarr/Sonarr sono fuori dal lock, come nel giro.
/// </summary>
public sealed partial class DownloadService
{
    /// <summary>Le ultime ricerche dell'admin che si ricordano (una per chiave); la più vecchia si dimentica.</summary>
    public const int MaxRememberedSearches = 20;

    // Solo sotto _lock. L'ultima ricerca dell'admin per chiave, solo in memoria.
    private readonly Dictionary<string, AdminSearch> _lastSearch = [];

    // Solo sotto _lock. Le chiavi con un download in corso (giro o admin): un secondo si salta (ruling 8).
    private readonly HashSet<string> _grabbing = [];

    // Il file di adesso; per una stagione il peso di tutti i file, punteggio e qualità del peggiore.
    private sealed record CurrentFile(long SizeBytes, int Score, int? QualityId, string Quality);

    // Una ricerca dell'admin: il titolo come lo vede il giro, il file, il profilo, le release e il risultato.
    // Solo stagioni: SeasonEpisodes i numeri di tutti i loro episodi (quelli di un pack intero), Episodes gli episodi
    // (con la serie) e Files i loro file.
    private sealed record AdminSearch(
        ArrTitle Title,
        CurrentFile? Current,
        ArrQualityProfile? Profile,
        IReadOnlyList<int>? SeasonEpisodes,
        IReadOnlyList<ArrRelease> Releases,
        DownloadSearchDto Result,
        DateTimeOffset At,
        IReadOnlyList<SonarrEpisode>? Episodes,
        IReadOnlyList<ArrFile> Files);

    // Il titolo di una chiave in Radarr/Sonarr e il file da leggere. Solo stagioni: gli episodi su cui misurare il pack, i
    // numeri di tutti e gli episodi.
    private sealed record AdminTarget(
        ArrTitle Title,
        UpgradeCheck? Files,
        IReadOnlyList<int>? RuleEpisodes = null,
        IReadOnlyList<int>? SeasonEpisodes = null,
        IReadOnlyList<SonarrEpisode>? Episodes = null);

    // Quello che scarica un grab dell'admin: la voce, il file di adesso e, per una stagione, gli episodi della release.
    private sealed record GrabTarget(ArrTitle Title, CurrentFile? Current, List<int>? EpisodeNumbers);

    /// <summary>
    /// Cerca un titolo e applica la regola (spec T §8.2), anche senza una voce (per esempio da "Da ripassare"). Null per una
    /// chiave non valida o un titolo che Radarr/Sonarr non hanno; un loro errore va in <c>Error</c>, con le liste vuote.
    /// </summary>
    public async Task<DownloadSearchDto?> SearchAsync(string key, CancellationToken cancellationToken)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return null;
        }

        var (search, error) = await ReadAsync(ServiceOf(parsed.Kind), c => RunSearchAsync(parsed, c), cancellationToken).ConfigureAwait(false);
        if (error is null)
        {
            return search?.Result;
        }

        string title;
        lock (_lock)
        {
            title = Book.Get(parsed.ToString())?.Title ?? "";
        }

        return new DownloadSearchDto(parsed.ToString(), parsed.Kind, title, 0, null, [], [], 0, 0, error, []);
    }

    /// <summary>
    /// Scarica una release dell'ultima ricerca dell'admin (spec T §8.2), anche al posto del download in corso ("cambia").
    /// Se Radarr/Sonarr hanno dimenticato i risultati (dopo circa 30 minuti) si cerca di nuovo e si riprova una volta (spec T §11).
    /// </summary>
    public async Task<GrabOutcome> GrabAsync(string key, string guid, int indexerId, CancellationToken cancellationToken)
    {
        if (!DownloadKey.TryParse(key, out var parsed) || string.IsNullOrEmpty(guid))
        {
            return GrabOutcome.Invalid;
        }

        lock (_lock)
        {
            if (!_grabbing.Add(parsed.ToString()))
            {
                return GrabOutcome.Busy;
            }
        }

        // Le chiavi tenute da questo grab: quella dell'admin e, per un singolo da una ricerca di stagione, quella dell'episodio.
        List<string> guarded = [parsed.ToString()];
        try
        {
            return await GrabGuardedAsync(parsed, guid, indexerId, guarded, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            lock (_lock)
            {
                guarded.ForEach(k => _grabbing.Remove(k));
            }
        }
    }

    private async Task<GrabOutcome> GrabGuardedAsync(DownloadKey parsed, string guid, int indexerId, List<string> guarded, CancellationToken cancellationToken)
    {
        var service = ServiceOf(parsed.Kind);
        AdminSearch? search;
        lock (_lock)
        {
            search = _lastSearch.GetValueOrDefault(parsed.ToString());
        }

        var searchedAgain = false;
        var oldRemoved = false;
        while (true)
        {
            if (search is null || search.Releases.FirstOrDefault(r => r.Guid == guid && r.IndexerId == indexerId) is not { } release)
            {
                if (searchedAgain)
                {
                    return GrabOutcome.Expired;
                }

                var (fresh, error) = await ReadAsync(service, c => RunSearchAsync(parsed, c), cancellationToken).ConfigureAwait(false);
                if (error is not null)
                {
                    return GrabOutcome.Unavailable;
                }

                if (fresh is null)
                {
                    return GrabOutcome.Invalid;
                }

                (search, searchedAgain) = (fresh, true);
                continue;
            }

            // Prima si toglie il download di prima, così non arrivano due copie (spec T §8.2); per un singolo da una
            // ricerca di stagione anche quello del suo episodio.
            var target = GrabTargetOf(search, release, time.GetUtcNow());
            if (!guarded.Contains(target.Title.Key))
            {
                lock (_lock)
                {
                    // Il giro sta scaricando quell'episodio: come per la chiave dell'admin (ruling 8).
                    if (!_grabbing.Add(target.Title.Key))
                    {
                        return GrabOutcome.Busy;
                    }
                }

                guarded.Add(target.Title.Key);
            }

            if (!oldRemoved
                && (!await RemoveOldDownloadAsync(parsed, service, cancellationToken).ConfigureAwait(false)
                    || (target.Title.Key != parsed.ToString()
                        && DownloadKey.TryParse(target.Title.Key, out var episode)
                        && !await RemoveOldDownloadAsync(episode, service, cancellationToken).ConfigureAwait(false))))
            {
                return GrabOutcome.Unavailable;
            }

            oldRemoved = true;
            try
            {
                await arr.GrabReleaseAsync(service, guid, indexerId, cancellationToken).ConfigureAwait(false);
            }
            catch (ArrException ex) when (ex.Status is 404 or 400)
            {
                // Risultati scaduti in Radarr/Sonarr: una nuova ricerca, se non è già quella di adesso.
                if (searchedAgain)
                {
                    return GrabOutcome.Expired;
                }

                search = null;
                continue;
            }
            catch (ArrException ex) when (ex.Status >= 500)
            {
                // Radarr/Sonarr hanno risposto: non è un servizio che non risponde (spec T §8.2).
                logger.LogWarning("Download automatici: {Key}, {Kind} ha rifiutato la release dell'admin ({Error})", search.Title.Key, service, ErrorOf(ex));
                return GrabOutcome.Refused;
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning("Download automatici: {Key}, {Kind} non ha scaricato la release dell'admin ({Error})", search.Title.Key, service, ErrorOf(ex));
                return GrabOutcome.Unavailable;
            }

            logger.LogInformation("Download automatici: {Key} scaricato da {Kind} per l'admin", target.Title.Key, service);
            GrabbedByAdmin(search, target, release);
            return GrabOutcome.Ok;
        }
    }

    /// <summary>"Va bene così" (spec T §6): il titolo esce da "Da ripassare" e non ci torna; falso per una chiave non valida.</summary>
    public bool Accept(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return false;
        }

        lock (_lock)
        {
            Book.Accept(parsed.ToString());
            store.Save(Book);
        }

        return true;
    }

    /// <summary>La voce si cerca al prossimo giro, chiesto subito (spec T §7.4); falso se la chiave non ha una voce.</summary>
    public bool SearchNow(string key)
    {
        lock (_lock)
        {
            if (!DownloadKey.TryParse(key, out var parsed) || Book.Get(parsed.ToString()) is not { } entry)
            {
                return false;
            }

            entry.NextSearchAt = time.GetUtcNow();
            store.Save(Book);
        }

        Nudge();
        return true;
    }

    /// <summary>La panoramica (spec T §8.1), tutta dal libro: scelte dalla più recente, voci seguite, "Da ripassare", errori dell'ultimo giro.</summary>
    public DownloadsOverviewDto Overview()
    {
        var since = time.GetUtcNow() - DownloadBook.ChoiceRetention;
        lock (_lock)
        {
            // Prune gira solo a fine giro: le scelte vecchie si filtrano anche qui.
            return new DownloadsOverviewDto(
                settings.Enabled,
                [.. Book.Choices.Where(c => c.At >= since).Select(ChoiceDto)],
                [.. Book.Entries
                    .Where(e => e.State is DownloadStates.Waiting or DownloadStates.NeedsYou or DownloadStates.Downloading or DownloadStates.UpgradeWatch)
                    .OrderBy(e => e.NextSearchAt)
                    .Select(e => new DownloadItemDto(e.Key, e.Kind, e.Title, e.PosterUrl, e.State, e.Reason, e.AvailableSince, e.LastSearchAt, e.NextSearchAt))],
                [.. Book.Review
                    .Where(r => !Book.IsAccepted(r.Key))
                    .Select(r => new ReviewItemDto(r.Key, r.Kind, r.Title, r.PosterUrl, r.Score, r.SizeBytes, r.Quality))],
                Book.ReviewAt,
                _lastErrors.Sonarr,
                _lastErrors.Radarr);
        }
    }

    /// <summary>
    /// I profili di qualità di Radarr e Sonarr con le loro soglie (spec T §7.1); un servizio in errore non c'è. Null se
    /// nessun servizio configurato ha risposto (ruling 14): la pagina mostra "Profiles not available", non "nessun profilo".
    /// </summary>
    public async Task<IReadOnlyList<DownloadProfileDto>?> ProfilesAsync(CancellationToken cancellationToken)
    {
        var result = new List<DownloadProfileDto>();
        var (configured, answered) = (0, 0);
        foreach (var kind in new[] { ArrKind.Radarr, ArrKind.Sonarr })
        {
            var (profiles, error) = await ReadAsync(kind, c => arr.GetQualityProfilesAsync(kind, c), cancellationToken).ConfigureAwait(false);
            configured += error == UpcomingErrors.NotConfigured ? 0 : 1;
            answered += profiles is null ? 0 : 1;
            foreach (var profile in profiles?.OfType<ArrQualityProfile>() ?? [])
            {
                var thresholds = settings.For(kind, profile.Id, profile.Name);
                result.Add(new DownloadProfileDto(kind.ToString(), profile.Id, profile.Name ?? "", thresholds.MinScore, thresholds.TargetScore));
            }
        }

        return configured > 0 && answered == 0 ? null : result;
    }

    // Fuori dal lock: titolo, file, profilo e release, poi la regola; la ricerca si ricorda per il grab.
    private async Task<AdminSearch?> RunSearchAsync(DownloadKey key, CancellationToken cancellationToken)
    {
        if (await ReadTargetAsync(key, cancellationToken).ConfigureAwait(false) is not { } target)
        {
            return null;
        }

        var service = ServiceOf(key.Kind);
        var context = await ReadContextAsync(service)(cancellationToken).ConfigureAwait(false);
        var releases = (await arr.SearchReleasesAsync(service, QueryOf(key), cancellationToken).ConfigureAwait(false)).OfType<ArrRelease>().ToList();
        var files = target.Files is { } check ? await CurrentFilesAsync(check, cancellationToken).ConfigureAwait(false) : [];
        var current = CurrentOf(files);

        var title = target.Title;
        var profile = context.Profiles.GetValueOrDefault(title.ProfileId);
        var thresholds = settings.For(service, title.ProfileId, profile?.Name);
        var input = new RuleInput(title.RuntimeMinutes, service == ArrKind.Radarr, settings.MinGbPerHour, thresholds.MinScore, context.IndexerPriority);
        var (rule, choice) = ApplyRule(releases, input, target.RuleEpisodes);
        var result = new DownloadSearchDto(
            title.Key,
            title.Kind,
            title.Title,
            title.RuntimeMinutes,
            current is null ? null : new DownloadCurrentFileDto(current.SizeBytes, current.Score, current.Quality),
            [.. rule.Candidates.Select((r, i) => new DownloadCandidateDto(i + 1, ReleaseDto(r), ReferenceEquals(r, choice), WouldImport(profile, current, r)))],
            [.. rule.Rejected.Select(r => new DownloadRejectedDto(ReleaseDto(r.Release), r.Reason, r.Detail))],
            rule.Candidates.Count,
            releases.Count(r => !string.IsNullOrEmpty(r.Guid)),
            null,
            choice is null ? EpisodeChoicesOf(target, releases, files, input, thresholds.TargetScore, profile, time.GetUtcNow()) : []);

        var search = new AdminSearch(title, current, profile, target.SeasonEpisodes, releases, result, time.GetUtcNow(), target.Episodes, files);
        lock (_lock)
        {
            _lastSearch[title.Key] = search;
            if (_lastSearch.Count > MaxRememberedSearches)
            {
                _lastSearch.Remove(_lastSearch.Values.MinBy(s => s.At)!.Title.Key);
            }
        }

        return search;
    }

    // Il titolo come lo costruisce il giro; null se Radarr/Sonarr non l'hanno.
    private async Task<AdminTarget?> ReadTargetAsync(DownloadKey key, CancellationToken cancellationToken)
    {
        if (key.Kind == DownloadKinds.Movie)
        {
            // Solo il film, non tutta la libreria (ruling 14). 404: Radarr non l'ha.
            RadarrMovie movie;
            try
            {
                movie = await arr.GetMovieAsync(key.Id, cancellationToken).ConfigureAwait(false);
            }
            catch (ArrException ex) when (ex.Status == 404)
            {
                return null;
            }

            var title = MovieTitleOf(movie);
            return new AdminTarget(title, title.FileId > 0 ? new UpgradeCheck(title.Key, ArrKind.Radarr, title.FileId, 0, 0) : null);
        }

        var now = time.GetUtcNow();
        if (key.Kind == DownloadKinds.Episode)
        {
            // Un episodio: una chiamata, la serie è dentro (verificato su Sonarr). 404: Sonarr non l'ha.
            SonarrEpisode episode;
            try
            {
                episode = await arr.GetEpisodeAsync(key.Id, cancellationToken).ConfigureAwait(false);
            }
            catch (ArrException ex) when (ex.Status == 404)
            {
                return null;
            }

            var title = EpisodeTitleOf(episode, now);
            return new AdminTarget(title, episode.EpisodeFileId > 0 ? new UpgradeCheck(title.Key, ArrKind.Sonarr, 0, episode.SeriesId, key.Id) : null);
        }

        // Una stagione.
        var series = await arr.GetSeriesAsync(cancellationToken).ConfigureAwait(false);
        if (series.FirstOrDefault(s => s?.Id == key.Id) is not { } show)
        {
            return null;
        }

        var episodes = (await arr.GetSeriesEpisodesAsync(show.Id, cancellationToken).ConfigureAwait(false))
            .OfType<SonarrEpisode>().Where(e => e.SeasonNumber == key.Season).ToList();
        if (episodes.Count == 0)
        {
            return null;
        }

        // Il titolo di un episodio (per un singolo della ricerca) viene dalla sua serie.
        foreach (var episode in episodes)
        {
            episode.Series ??= show;
        }

        // Il pack si misura sugli episodi che mancano, come nel giro; senza mancanti (da "Da ripassare") su tutti.
        var all = episodes.Select(e => e.EpisodeNumber).Distinct().Order().ToList();
        var missing = episodes.Where(e => e.Monitored && !e.HasFile && e.AirDateUtc <= now).Select(e => e.EpisodeNumber).Distinct().Order().ToList();
        var seasonTitle = new ArrTitle(
            key.ToString(),
            DownloadKinds.Season,
            SeasonTitleOf(show.Title, key.Season),
            Poster(show.Images),
            show.QualityProfileId,
            show.Runtime,
            episodes.Max(e => e.AirDateUtc),
            Monitored: true,
            Followed: true,
            Wanted: missing.Count > 0,
            HasFile: missing.Count == 0,
            SeriesId: show.Id);
        return new AdminTarget(seasonTitle, new UpgradeCheck(seasonTitle.Key, ArrKind.Sonarr, 0, show.Id, 0, key.Season), missing.Count > 0 ? missing : all, all, episodes);
    }

    // Il file di adesso: il peso di tutti i file, punteggio e qualità del peggiore; null senza file.
    private static CurrentFile? CurrentOf(IReadOnlyList<ArrFile> files) =>
        files.MinBy(f => f.CustomFormatScore) is not { } worst
            ? null
            : new CurrentFile(files.Sum(f => f.Size), worst.CustomFormatScore, worst.Quality?.Quality?.Id, worst.Quality?.Quality?.Name ?? "");

    // Una stagione: la release copre i suoi episodi (un pack intero tutti) e il file di adesso è quello di quegli episodi; un
    // singolo è una voce del suo episodio (ruling 13). Film ed episodi: il titolo e il file della ricerca.
    private static GrabTarget GrabTargetOf(AdminSearch search, ArrRelease release, DateTimeOffset now)
    {
        if (search.Episodes is not { } episodes || search.SeasonEpisodes is not { } all)
        {
            return new GrabTarget(search.Title, search.Current, null);
        }

        var partial = !release.FullSeason && release.EpisodeNumbers is { Count: > 0 };
        List<int> numbers = partial ? [.. release.EpisodeNumbers!] : [.. all];
        var covered = episodes.Where(e => numbers.Contains(e.EpisodeNumber)).ToList();
        var fileIds = covered.Select(e => e.EpisodeFileId).Where(id => id > 0).ToHashSet();
        var current = CurrentOf([.. search.Files.Where(f => fileIds.Contains(f.Id))]);
        return partial && numbers is [_] && covered is [var episode]
            ? new GrabTarget(EpisodeTitleOf(episode, now), current, null)
            : new GrabTarget(search.Title, current, numbers);
    }

    // La regola sulle release di una ricerca. Una stagione: ogni release si misura sui suoi episodi (un pack su quelli
    // della regola, come nel giro) e la scelta è quella del pack (spec T §5.4).
    private static (RuleResult Rule, ArrRelease? Choice) ApplyRule(IReadOnlyList<ArrRelease> releases, RuleInput input, IReadOnlyList<int>? seasonEpisodes)
    {
        if (seasonEpisodes is null)
        {
            var single = DownloadRule.Choose(releases, input);
            return (single, single.Choice);
        }

        var minutes = input.RuntimeMinutes > 0 ? input.RuntimeMinutes : DownloadRule.FallbackEpisodeMinutes;
        var valid = new List<ArrRelease>();
        var rejected = new List<RuleRejected>();
        foreach (var release in releases)
        {
            var episodes = release.FullSeason ? seasonEpisodes.Count : Math.Max(1, release.EpisodeNumbers?.Count ?? 0);
            var one = DownloadRule.Choose([release], input with { RuntimeMinutes = minutes * episodes });
            valid.AddRange(one.Candidates);
            rejected.AddRange(one.Rejected);
        }

        // Già misurate: qui serve solo l'ordine della regola, con la scelta del pack al primo posto.
        var ordered = DownloadRule.Choose(valid, input with { MinGbPerHour = 0 });
        var choice = SeasonPackRule.ChoosePack(releases, seasonEpisodes, input);
        return (ordered with { Candidates = [.. ordered.Candidates.OrderBy(r => !ReferenceEquals(r, choice))], Rejected = rejected }, choice);
    }

    // Stagione senza un pack scelto (spec T §5.4, §8.2): il singolo migliore di ogni episodio, nella stessa scelta del giro.
    // Gli episodi sono quelli che mancano; senza mancanti quelli monitorati e già usciti con il file sotto l'obiettivo (senza
    // obiettivo tutti): un episodio che l'admin ha tolto dal monitoraggio non si scarica con "Scarica tutti". Una stagione
    // senza nessun episodio monitorato (serie tolta dal monitoraggio) li conta tutti: l'admin l'ha cercata apposta.
    // WouldImport si misura sul file di quell'episodio, non sul peggiore della stagione.
    private static List<DownloadEpisodeChoiceDto> EpisodeChoicesOf(
        AdminTarget target, IReadOnlyList<ArrRelease> releases, IReadOnlyList<ArrFile> files, RuleInput input, int? targetScore, ArrQualityProfile? profile, DateTimeOffset now)
    {
        var episodes = target.Episodes ?? [];
        var anyMonitored = episodes.Any(e => e.Monitored);
        var singles = releases.Where(r => !r.FullSeason && r.EpisodeNumbers is { Count: 1 }).ToLookup(r => r.EpisodeNumbers![0]);
        var result = new List<DownloadEpisodeChoiceDto>();
        foreach (var number in target.RuleEpisodes ?? [])
        {
            if (!target.Title.Wanted && !episodes.Any(e => e.EpisodeNumber == number && (e.Monitored || !anyMonitored) && e.AirDateUtc <= now))
            {
                continue;
            }

            var fileIds = episodes.Where(e => e.EpisodeNumber == number).Select(e => e.EpisodeFileId).Where(id => id > 0).ToHashSet();
            var current = CurrentOf([.. files.Where(f => fileIds.Contains(f.Id))]);
            if (!target.Title.Wanted && targetScore is { } goal && current is not null && current.Score >= goal)
            {
                continue;
            }

            var choice = DownloadRule.Choose(singles[number], input).Choice;
            result.Add(new DownloadEpisodeChoiceDto(number, choice is null ? null : ReleaseDto(choice), choice is not null && WouldImport(profile, current, choice), current?.Score));
        }

        return result;
    }

    // Radarr/Sonarr importerebbero la release al posto del file di adesso? Senza profilo no (spec T §5.3b).
    private static bool WouldImport(ArrQualityProfile? profile, CurrentFile? current, ArrRelease release) =>
        profile is not null
        && DownloadRule.WouldImport(profile, release.Quality?.Quality?.Id ?? 0, release.CustomFormatScore, current?.QualityId, current?.Score);

    // "cambia" (spec T §8.2): tutto quello che il titolo ha in coda si toglie, anche dal client, senza blocklist; anche un
    // download fermo in "Serve te" o appena scelto (QueueId non ancora letto). Falso se non si è potuto.
    private async Task<bool> RemoveOldDownloadAsync(DownloadKey key, ArrKind service, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            if (Book.Get(key.ToString()) is not { } entry || (entry.QueueId is null && entry.State != DownloadStates.Downloading))
            {
                return true;
            }
        }

        try
        {
            var queue = (await arr.GetQueueAsync(service, cancellationToken).ConfigureAwait(false)).OfType<ArrQueueItem>();
            List<int> ids = key.Kind switch
            {
                DownloadKinds.Movie => [.. queue.Where(q => q.MovieId == key.Id).Select(q => q.Id)],
                DownloadKinds.Episode => [.. queue.Where(q => q.EpisodeId == key.Id).Select(q => q.Id)],

                // Un pack ha un elemento per episodio, dal più basso: si tolgono tutti (come un pack fermo).
                _ => [.. SeasonQueueOf(queue).GetValueOrDefault(key.ToString())?.Select(q => q.Id) ?? []],
            };

            for (var i = 0; i < ids.Count; i++)
            {
                try
                {
                    await arr.RemoveFromQueueAsync(service, ids[i], blocklist: false, removeFromClient: true, cancellationToken).ConfigureAwait(false);
                }
                catch (ArrException ex) when (ex.Status == 404)
                {
                    // Già importato, o tolto insieme al torrent del pack: non c'è più, si va avanti.
                }
                catch (Exception ex) when (i > 0 && !cancellationToken.IsCancellationRequested)
                {
                    // Il primo toglie il torrent del pack: gli altri elementi possono non esserci più.
                    logger.LogWarning("Download automatici: {Key}, {Kind} non ha tolto un elemento del pack ({Error})", key.ToString(), service, ErrorOf(ex));
                }
            }
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download automatici: {Key}, {Kind} non ha tolto il download di prima ({Error})", key.ToString(), service, ErrorOf(ex));
            return false;
        }

        return true;
    }

    // Dopo un grab riuscito: la voce (creata se manca, per esempio da "Da ripassare") scarica la scelta dell'admin.
    // Con un file presente è un upgrade, che il giro conferma dal file (ruling 5-6); se Radarr/Sonarr non lo
    // importerebbero si importa a mano (decisione 9).
    private void GrabbedByAdmin(AdminSearch search, GrabTarget target, ArrRelease release)
    {
        lock (_lock)
        {
            var now = time.GetUtcNow();
            var entry = Book.Get(target.Title.Key) ?? Create(target.Title, now);
            Describe(entry, target.Title);
            if (target.Current is { } file)
            {
                (entry.CurrentScore, entry.CurrentQualityId, entry.CurrentSizeBytes) = (file.Score, file.QualityId, file.SizeBytes);
            }

            Grabbed(entry, release, upgrade: target.Current is not null, search.Profile?.Name, now, byAdmin: true);

            // Il download di prima non c'è più: il giro aspetta il nuovo in coda, come dopo ogni scelta.
            entry.QueueId = null;
            entry.LastSizeLeft = null;
            entry.LastProgressAt = null;
            entry.ManualImportPending = target.Current is not null && !WouldImport(search.Profile, target.Current, release);
            entry.EpisodeNumbers = target.EpisodeNumbers;
            Book.RemoveFromReview(entry.Key);

            // Un singolo al posto della stagione: la voce di stagione esce (il suo pack, se c'era, è già tolto), salvo che
            // tenga d'occhio un upgrade; gli altri episodi tornano voci al giro dopo.
            if (target.Title.Key != search.Title.Key && Book.Get(search.Title.Key) is { State: not DownloadStates.UpgradeWatch })
            {
                Book.Remove(search.Title.Key);
            }

            // Un pack: gli episodi che copre e che aspettano escono subito, così un giro in corso non li scarica; quelli che
            // scaricano o tengono d'occhio un upgrade restano.
            foreach (var episode in (search.Episodes ?? []).Where(e => target.EpisodeNumbers?.Contains(e.EpisodeNumber) == true))
            {
                if (Book.Get(Key(DownloadKinds.Episode, episode.Id)) is { State: DownloadStates.Waiting or DownloadStates.NeedsYou } waiting)
                {
                    Book.Remove(waiting.Key);
                }
            }

            // Subito su disco, come dopo un grab del giro.
            store.Save(Book);
        }
    }

    private static DownloadReleaseDto ReleaseDto(ArrRelease r) =>
        new(r.Guid ?? "", r.IndexerId, r.Indexer ?? "", r.Title ?? "", r.Quality?.Quality?.Name ?? "", r.Quality?.Quality?.Resolution ?? 0, r.Size, r.CustomFormatScore, r.Seeders);

    private static DownloadChoiceDto ChoiceDto(DownloadChoice c) => new(
        c.Key,
        c.Kind,
        c.Title,
        c.PosterUrl,
        c.At,
        new DownloadReleaseDto(c.Guid, c.IndexerId, c.Indexer, c.ReleaseTitle, c.Quality, c.Resolution, c.SizeBytes, c.Score, c.Seeders),
        c.PreviousSizeBytes,
        c.PreviousScore,
        c.ByAdmin);
}
