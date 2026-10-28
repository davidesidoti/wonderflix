using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Il giro, seconda parte (spec T §5): la ricerca dei titoli che mancano, la scelta con la regola, gli upgrade.</summary>
public sealed partial class DownloadService
{
    // Letti una volta per giro e servizio: i profili per id e la priorità di ogni indexer.
    private sealed record SearchContext(IReadOnlyDictionary<int, ArrQualityProfile> Profiles, IReadOnlyDictionary<int, int> IndexerPriority);

    // Una voce da cercare, copiata sotto il lock. Solo stagioni: i numeri degli episodi per il pack e le voci in cui si divide.
    private sealed record SearchItem(
        string Key,
        ArrKind Service,
        string Query,
        bool Upgrade,
        int ProfileId,
        int RuntimeMinutes,
        int? CurrentScore,
        int? CurrentQualityId,
        IReadOnlyList<int>? Episodes = null,
        IReadOnlyList<ArrTitle>? SplitInto = null);

    // Le voci con la ricerca scaduta, dalla più vecchia; al massimo MaxSearchesPerCycle ricerche, una alla volta.
    private async Task<(int Searched, int Grabbed)> SearchDueAsync(
        IReadOnlyDictionary<ArrKind, ArrView> views, Dictionary<ArrKind, string?> errors, CancellationToken cancellationToken)
    {
        List<string> due;
        lock (_lock)
        {
            var now = time.GetUtcNow();
            due = [.. Book.Entries.Where(e => IsDue(e, views, now)).OrderBy(e => e.NextSearchAt).Select(e => e.Key)];
        }

        var contexts = new Dictionary<ArrKind, SearchContext?>();
        var searched = 0;
        var grabbed = 0;
        foreach (var key in due)
        {
            if (searched == MaxSearchesPerCycle)
            {
                break;
            }

            SearchItem? item;
            lock (_lock)
            {
                item = Book.Get(key) is { } entry && IsDue(entry, views, time.GetUtcNow()) ? ToSearchItem(entry, views[ServiceOf(entry.Kind)]) : null;
            }

            if (item is null)
            {
                continue;
            }

            if (!contexts.TryGetValue(item.Service, out var context))
            {
                context = (await ReadAsync(item.Service, ReadContextAsync(item.Service), cancellationToken).ConfigureAwait(false)) switch
                {
                    (_, { } error) => Failed(item.Service, error),
                    var (value, _) => value,
                };
                contexts[item.Service] = context;
            }

            if (context is null)
            {
                // Senza profili o indexer non si cerca con quel servizio: le voci restano come sono.
                continue;
            }

            if (searched > 0)
            {
                await Task.Delay(Pause, time, cancellationToken).ConfigureAwait(false);
            }

            // L'admin può spegnere a metà giro: si ferma dopo il titolo in corso (spec T §11).
            if (!settings.Enabled)
            {
                break;
            }

            searched++;
            if (await SearchOneAsync(item, context, cancellationToken).ConfigureAwait(false))
            {
                grabbed++;
            }
        }

        return (searched, grabbed);

        SearchContext? Failed(ArrKind kind, string error)
        {
            errors[kind] = error;
            return null;
        }
    }

    private Func<CancellationToken, Task<SearchContext>> ReadContextAsync(ArrKind kind) => async cancellationToken =>
    {
        var profiles = await arr.GetQualityProfilesAsync(kind, cancellationToken).ConfigureAwait(false);
        var indexers = await arr.GetIndexersAsync(kind, cancellationToken).ConfigureAwait(false);
        return new SearchContext(
            ByKey(profiles.OfType<ArrQualityProfile>(), p => p.Id),
            ByKey(indexers.OfType<ArrIndexer>(), i => i.Id).ToDictionary(p => p.Key, p => p.Value.Priority));
    };

    // Solo sotto _lock. Waiting e NeedsYou (non ImportBlocked) di un titolo ancora da scaricare, o UpgradeWatch;
    // solo per i servizi letti in questo giro: degli altri non si sa se il titolo è in coda.
    private static bool IsDue(DownloadEntry entry, IReadOnlyDictionary<ArrKind, ArrView> views, DateTimeOffset now) =>
        entry.NextSearchAt <= now
        && views.TryGetValue(ServiceOf(entry.Kind), out var view)
        && entry.State switch
        {
            DownloadStates.UpgradeWatch => true,
            DownloadStates.Waiting => view.Titles.GetValueOrDefault(entry.Key)?.Wanted == true,
            DownloadStates.NeedsYou => entry.Reason != DownloadReasons.ImportBlocked && view.Titles.GetValueOrDefault(entry.Key)?.Wanted == true,
            _ => false,
        };

    private static SearchItem? ToSearchItem(DownloadEntry entry, ArrView view)
    {
        if (!DownloadKey.TryParse(entry.Key, out var key))
        {
            return null;
        }

        var (service, query) = (ServiceOf(key.Kind), QueryOf(key));
        var upgrade = entry.State == DownloadStates.UpgradeWatch;
        var item = new SearchItem(entry.Key, service, query, upgrade, entry.ProfileId, entry.RuntimeMinutes, entry.CurrentScore, entry.CurrentQualityId);
        if (key.Kind != DownloadKinds.Season)
        {
            return item;
        }

        // Gli episodi che mancano, o per un upgrade quelli del pack scaricato.
        var season = view.Seasons?.GetValueOrDefault(entry.Key);
        var episodes = upgrade ? entry.EpisodeNumbers : season?.Missing;
        return episodes is { Count: > 0 } ? item with { Episodes = episodes, SplitInto = season?.Episodes } : null;
    }

    // La query di release per la chiave.
    private static string QueryOf(DownloadKey key) => key.Kind switch
    {
        DownloadKinds.Movie => string.Create(CultureInfo.InvariantCulture, $"movieId={key.Id}"),
        DownloadKinds.Episode => string.Create(CultureInfo.InvariantCulture, $"episodeId={key.Id}"),
        _ => string.Create(CultureInfo.InvariantCulture, $"seriesId={key.Id}&seasonNumber={key.Season}"),
    };

    // Una ricerca e quello che ne segue; true se ha scaricato.
    private async Task<bool> SearchOneAsync(SearchItem item, SearchContext context, CancellationToken cancellationToken)
    {
        var profile = context.Profiles.GetValueOrDefault(item.ProfileId);
        IReadOnlyList<ArrRelease?> releases;
        try
        {
            releases = await arr.SearchReleasesAsync(item.Service, item.Query, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download automatici: ricerca di {Key} su {Kind} non riuscita ({Error})", item.Key, item.Service, ErrorOf(ex));
            Update(item.Key, (entry, now) =>
            {
                // Si riprova al giro dopo, ma dietro alle voci che aspettano già.
                entry.LastSearchAt = now;
                entry.Reason = DownloadReasons.SearchFailed;
                entry.NextSearchAt = now + CycleInterval;
            });
            return false;
        }

        var thresholds = settings.For(item.Service, item.ProfileId, profile?.Name);
        var input = new RuleInput(item.RuntimeMinutes, item.Service == ArrKind.Radarr, settings.MinGbPerHour, thresholds.MinScore, context.IndexerPriority);
        ArrRelease? choice;
        var belowMinScore = false;
        if (item.Episodes is { } episodes)
        {
            // Una stagione: il pack se conviene (spec T §5.4), altrimenti si divide; un upgrade resta com'è.
            choice = SeasonPackRule.ChoosePack(releases, episodes, input);
            if (choice is null && !item.Upgrade)
            {
                Split(item);
                return false;
            }
        }
        else
        {
            var result = DownloadRule.Choose(releases, input);
            (choice, belowMinScore) = (result.Choice, result.BelowMinScore);
        }

        if (choice is not null && item.Upgrade && !IsUpgrade(choice, item, profile))
        {
            choice = null;
        }

        if (choice is null)
        {
            Update(item.Key, (entry, now) => NothingChosen(entry, belowMinScore, now));
            return false;
        }

        // La ricerca dura fino a 2 minuti: nel frattempo la voce può essere sparita o già in download, o l'admin la sta scaricando.
        lock (_lock)
        {
            if (Book.Get(item.Key) is not { } current || current.State == DownloadStates.Downloading || !_grabbing.Add(item.Key))
            {
                return false;
            }
        }

        try
        {
            return await GrabChoiceAsync(item, choice, profile, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            lock (_lock)
            {
                _grabbing.Remove(item.Key);
            }
        }
    }

    // Il grab della scelta del giro; true se ha scaricato.
    private async Task<bool> GrabChoiceAsync(SearchItem item, ArrRelease choice, ArrQualityProfile? profile, CancellationToken cancellationToken)
    {
        try
        {
            await arr.GrabReleaseAsync(item.Service, choice.Guid!, choice.IndexerId, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download automatici: {Key}, {Kind} non ha scaricato la scelta ({Error})", item.Key, item.Service, ErrorOf(ex));
            Update(item.Key, (entry, now) =>
            {
                // Spesso il client di download giù per poco: si riprova al giro dopo, come per la ricerca.
                entry.LastSearchAt = now;
                entry.Reason = DownloadReasons.SearchFailed;
                entry.NextSearchAt = now + CycleInterval;
            });
            return false;
        }

        logger.LogInformation("Download automatici: {Key} scaricato da {Kind}", item.Key, item.Service);
        lock (_lock)
        {
            if (Book.Get(item.Key) is { } entry)
            {
                Grabbed(entry, choice, item.Upgrade, profile?.Name, time.GetUtcNow());
                entry.EpisodeNumbers = item.Episodes?.ToList();
            }

            // Subito su disco: un riavvio prima della fine del giro non deve perdere il download.
            store.Save(Book);
        }

        return true;
    }

    // Un upgrade si scarica solo con un punteggio più alto e se Radarr/Sonarr lo importerebbero (spec T §5.3b).
    private static bool IsUpgrade(ArrRelease choice, SearchItem item, ArrQualityProfile? profile) =>
        profile is not null
        && choice.CustomFormatScore > (item.CurrentScore ?? 0)
        && DownloadRule.WouldImport(profile, choice.Quality?.Quality?.Id ?? 0, choice.CustomFormatScore, item.CurrentQualityId, item.CurrentScore);

    // Applica il risultato sotto il lock, se la voce c'è ancora e non sta già scaricando (per esempio per l'admin).
    private void Update(string key, Action<DownloadEntry, DateTimeOffset> apply)
    {
        lock (_lock)
        {
            if (Book.Get(key) is { } entry && entry.State != DownloadStates.Downloading)
            {
                apply(entry, time.GetUtcNow());
            }
        }
    }

    // Solo sotto _lock (spec T §5.5).
    private static void NothingChosen(DownloadEntry entry, bool belowMinScore, DateTimeOffset now)
    {
        entry.LastSearchAt = now;
        entry.NextSearchAt = DownloadSchedule.Next(SinceOf(entry), now);
        if (entry.State == DownloadStates.UpgradeWatch)
        {
            // Il file c'è già: niente "Serve te".
            entry.Reason = null;
            return;
        }

        (entry.State, entry.Reason) =
            belowMinScore ? (DownloadStates.NeedsYou, DownloadReasons.BelowMinScore)
            : now - entry.AvailableSince >= DownloadSchedule.NeedsYouAfter ? (DownloadStates.NeedsYou, DownloadReasons.NothingFound)
            : (DownloadStates.Waiting, (string?)null);
    }

    // Solo sotto _lock. La voce scarica: CurrentScore e CurrentQualityId sono quelli della scelta.
    private void Grabbed(DownloadEntry entry, ArrRelease choice, bool upgrade, string? profileName, DateTimeOffset now, bool byAdmin = false)
    {
        var quality = choice.Quality?.Quality;
        Book.AddChoice(new DownloadChoice
        {
            Key = entry.Key,
            Kind = entry.Kind,
            Title = entry.Title,
            PosterUrl = entry.PosterUrl,
            At = now,
            Guid = choice.Guid ?? "",
            IndexerId = choice.IndexerId,
            Indexer = choice.Indexer ?? "",
            ReleaseTitle = choice.Title ?? "",
            Quality = quality?.Name ?? "",
            QualityId = quality?.Id ?? 0,
            Resolution = quality?.Resolution ?? 0,
            SizeBytes = choice.Size,
            Score = choice.CustomFormatScore,
            Seeders = choice.Seeders,

            // Il file che c'è adesso (dopo un upgrade fallito è ancora quello di prima, non l'ultima scelta).
            PreviousSizeBytes = upgrade ? entry.CurrentSizeBytes : null,
            PreviousScore = upgrade ? entry.CurrentScore : null,
            ByAdmin = byAdmin,
        });
        entry.State = DownloadStates.Downloading;
        entry.Reason = null;
        entry.LastSearchAt = now;
        entry.PreviousScore = upgrade ? entry.CurrentScore : null;
        entry.PreviousQualityId = upgrade ? entry.CurrentQualityId : null;
        entry.PreviousSizeBytes = upgrade ? entry.CurrentSizeBytes : null;
        entry.CurrentScore = choice.CustomFormatScore;
        entry.CurrentQualityId = quality?.Id;
        entry.CurrentSizeBytes = choice.Size;
        entry.ProfileName = profileName;

        // Solo per la release dell'admin che lo chiede (GrabbedByAdmin): un download nuovo non eredita quello di prima.
        entry.ManualImportPending = false;
    }

    // Un upgrade uscito dalla coda: il file da rileggere (film: id del file; episodio: serie ed episodio; stagione: serie e stagione).
    private sealed record UpgradeCheck(string Key, ArrKind Service, int MovieFileId, int SeriesId, int EpisodeId, int Season = 0);

    // Solo sotto _lock. Null se non si sa quale file leggere: vale la decisione 2.
    private static UpgradeCheck? UpgradeCheckOf(DownloadEntry entry, ArrTitle? title)
    {
        if (!DownloadKey.TryParse(entry.Key, out var key))
        {
            return null;
        }

        return key.Kind switch
        {
            DownloadKinds.Movie when title?.FileId > 0 => new UpgradeCheck(entry.Key, ArrKind.Radarr, title.FileId, 0, 0),
            DownloadKinds.Episode when entry.SeriesId > 0 => new UpgradeCheck(entry.Key, ArrKind.Sonarr, 0, entry.SeriesId, key.Id),
            DownloadKinds.Season when entry.SeriesId > 0 => new UpgradeCheck(entry.Key, ArrKind.Sonarr, 0, entry.SeriesId, 0, key.Season),
            _ => null,
        };
    }

    // Fuori dal lock: i file di adesso dicono se l'upgrade è arrivato. Lettura fallita: la voce resta Downloading, si riprova al giro dopo.
    private async Task ConfirmUpgradeAsync(UpgradeCheck check, CancellationToken cancellationToken)
    {
        IReadOnlyList<ArrFile> files;
        try
        {
            files = await CurrentFilesAsync(check, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download automatici: {Key}, {Kind} non ha dato il file ({Error})", check.Key, check.Service, ErrorOf(ex));
            return;
        }

        lock (_lock)
        {
            // PreviousScore c'è solo mentre l'upgrade scarica (anche in ImportBlocked): altrimenti è già cambiato tutto.
            if (Book.Get(check.Key) is not { PreviousScore: { } previousScore } entry)
            {
                return;
            }

            var now = time.GetUtcNow();

            // Ancora il file di prima (per una stagione tutti i suoi file): l'upgrade è fallito (Radarr/Sonarr hanno già messo la release in blocklist).
            if (files.Count > 0 && files.All(f => f.CustomFormatScore == previousScore && f.Quality?.Quality?.Id == entry.PreviousQualityId))
            {
                BackToUpgradeWatch(entry, now);
                return;
            }

            // Un file diverso: importato. Il punteggio vero è quello del file; per una stagione di più file resta quello del pack.
            if (files is [var file])
            {
                entry.CurrentScore = file.CustomFormatScore;
                entry.CurrentQualityId = file.Quality?.Quality?.Id;
                entry.CurrentSizeBytes = file.Size;
            }

            OnImported(entry, now);
        }
    }

    // Il file del film o dell'episodio (nessuno se non c'è), o i file della stagione.
    private async Task<IReadOnlyList<ArrFile>> CurrentFilesAsync(UpgradeCheck check, CancellationToken cancellationToken)
    {
        if (check.Service == ArrKind.Radarr)
        {
            var movieFiles = await arr.GetMovieFilesAsync([check.MovieFileId], cancellationToken).ConfigureAwait(false);
            return [.. movieFiles.OfType<ArrFile>().Where(f => f.Id == check.MovieFileId).Take(1)];
        }

        if (check.Season > 0)
        {
            var seasonFiles = await arr.GetEpisodeFilesAsync(check.SeriesId, cancellationToken).ConfigureAwait(false);
            return [.. seasonFiles.OfType<ArrFile>().Where(f => f.SeasonNumber == check.Season)];
        }

        var episodes = await arr.GetSeriesEpisodesAsync(check.SeriesId, cancellationToken).ConfigureAwait(false);
        var fileId = episodes.FirstOrDefault(e => e?.Id == check.EpisodeId)?.EpisodeFileId ?? 0;
        if (fileId == 0)
        {
            return [];
        }

        var episodeFiles = await arr.GetEpisodeFilesAsync(check.SeriesId, cancellationToken).ConfigureAwait(false);
        return [.. episodeFiles.OfType<ArrFile>().Where(f => f.Id == fileId).Take(1)];
    }

    // Solo sotto _lock. Upgrade fallito o fermo: si torna al file di prima, la finestra resta quella (spec T §5.3).
    private static void BackToUpgradeWatch(DownloadEntry entry, DateTimeOffset now)
    {
        entry.State = DownloadStates.UpgradeWatch;
        entry.Reason = null;
        entry.QueueId = null;
        entry.LastSizeLeft = null;
        entry.LastProgressAt = null;
        entry.CurrentScore = entry.PreviousScore;
        entry.CurrentQualityId = entry.PreviousQualityId;
        entry.CurrentSizeBytes = entry.PreviousSizeBytes;
        entry.PreviousScore = null;
        entry.PreviousQualityId = null;
        entry.PreviousSizeBytes = null;
        entry.NextSearchAt = DownloadSchedule.Next(SinceOf(entry), now);
    }

    // In UpgradeWatch il ritmo conta dalla scelta (UpgradeUntil − UpgradeWindow), altrimenti dalla disponibilità.
    private static DateTimeOffset SinceOf(DownloadEntry entry) =>
        entry.State == DownloadStates.UpgradeWatch && entry.UpgradeUntil is { } until ? until - DownloadSchedule.UpgradeWindow : entry.AvailableSince;

    // Solo sotto _lock. Choices va dalla più recente.
    private DownloadChoice? LatestChoice(string key) => Book.Choices.FirstOrDefault(c => c.Key == key);
}
