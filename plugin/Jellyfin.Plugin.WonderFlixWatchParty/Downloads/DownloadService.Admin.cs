using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Esito di un download scelto dall'admin (spec T §8.2): Invalid per una chiave o una release non valide, Expired se la
/// release non c'è più nemmeno in una nuova ricerca, Unavailable se Radarr/Sonarr non rispondono (ruling 7), Busy se
/// un download dello stesso titolo è già in corso, dal giro o da un altro admin (ruling 8), Refused se Radarr/Sonarr
/// hanno risposto con un errore, per esempio il client di download ha rifiutato il torrent (spec T §8.2). NothingToGrab
/// se "Scarica il migliore intanto" non trova più niente da prendere (spec §5.5).
/// </summary>
public enum GrabOutcome
{
    Ok,
    Invalid,
    Expired,
    Unavailable,
    Busy,
    Refused,
    NothingToGrab,
}

/// <summary>Il torrent già in qBittorrent che ha fatto rifiutare una release: da qui si possono importare i suoi file.</summary>
public sealed record ExistingTorrent(string Hash, string Name);

/// <summary>
/// Esito di "Importa comunque" e "Scarta e cerca un altro" (spec §4.4, §5.4): Invalid per una chiave non valida, Changed se la
/// voce non è più in <c>ImportBlocked</c>, Failed se l'import non è partito, Unavailable se Radarr/Sonarr non rispondono.
/// </summary>
public enum BlockedOutcome
{
    Ok,
    Invalid,
    Changed,
    Failed,
    Unavailable,
}

/// <summary>
/// Esito di "Cerca un upgrade" da "Da ripassare": Invalid per una chiave non valida, Changed se il titolo non è più da
/// ripassare né ha una voce da cercare (o è una riga salvata da una versione precedente, senza qualità).
/// </summary>
public enum HuntOutcome
{
    Ok,
    Invalid,
    Changed,
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

    // Solo sotto _lock. Le chiavi che il giro sta cercando adesso, con l'ora di inizio: la panoramica le mostra come "Searching".
    private readonly Dictionary<string, DateTimeOffset> _searching = [];

    // Il file di adesso; per una stagione il peso di tutti i file, punteggio e qualità del peggiore.
    private sealed record CurrentFile(long SizeBytes, int Score, int? QualityId, string Quality);

    // Una ricerca dell'admin: il titolo come lo vede il giro, il file, il profilo, le release, il risultato e i dati della regola.
    // Solo stagioni: SeasonEpisodes i numeri di tutti i loro episodi (quelli di un pack intero), Episodes gli episodi
    // (con la serie), Files i loro file e RuleEpisodes quelli su cui si misura un pack (i mancanti, come nel giro).
    private sealed record AdminSearch(
        ArrTitle Title,
        CurrentFile? Current,
        ArrQualityProfile? Profile,
        IReadOnlyList<int>? SeasonEpisodes,
        IReadOnlyList<ArrRelease> Releases,
        DownloadSearchDto Result,
        DateTimeOffset At,
        IReadOnlyList<SonarrEpisode>? Episodes,
        IReadOnlyList<ArrFile> Files,
        RuleInput Input,
        IReadOnlyList<int>? RuleEpisodes);

    // Il titolo di una chiave in Radarr/Sonarr e il file da leggere. Solo stagioni: gli episodi su cui misurare il pack, i
    // numeri di tutti e gli episodi.
    private sealed record AdminTarget(
        ArrTitle Title,
        UpgradeCheck? Files,
        IReadOnlyList<int>? RuleEpisodes = null,
        IReadOnlyList<int>? SeasonEpisodes = null,
        IReadOnlyList<SonarrEpisode>? Episodes = null);

    // Quello che scarica un grab dell'admin: la voce, il file di adesso e, per una stagione, gli episodi della release.
    // Monitored: Radarr/Sonarr seguono tutto quello che la release copre (serie compresa).
    private sealed record GrabTarget(ArrTitle Title, CurrentFile? Current, List<int>? EpisodeNumbers, bool Monitored);

    /// <summary>Un avviso agli admin per ogni voce che aspetta loro (stato <c>NeedsYou</c>).</summary>
    public IReadOnlyList<AdminAlert> NeedsYouAlerts()
    {
        lock (_lock)
        {
            return [.. Book.Entries
                .Where(e => e.State == DownloadStates.NeedsYou)
                .Select(e => new AdminAlert("download:" + e.Key, InboxEntryTypes.DownloadNeedsYou, e.Title, Reason: e.Reason))];
        }
    }

    /// <summary>
    /// Cerca un titolo e applica la regola (spec T §8.2), anche senza una voce (per esempio da "Da ripassare"). Null per una
    /// chiave non valida o un titolo che Radarr/Sonarr non hanno; un loro errore va in <c>Error</c>, con le liste vuote.
    /// Per le app 0.27.x (spec W §4.4): avvia una ricerca nuova in background, o aggancia quella in corso, e la aspetta;
    /// <paramref name="cancellationToken"/> annulla solo l'attesa, non la ricerca.
    /// </summary>
    public async Task<DownloadSearchDto?> SearchAsync(string key, CancellationToken cancellationToken)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return null;
        }

        Task<SearchOutcome> work;
        lock (_lock)
        {
            work = JobFor(parsed, again: true).Work;
        }

        return (await work.WaitAsync(cancellationToken).ConfigureAwait(false)).Result;
    }

    /// <summary>
    /// Scarica una release dell'ultima ricerca dell'admin (spec T §8.2), anche al posto del download in corso ("cambia").
    /// Se Radarr/Sonarr hanno dimenticato i risultati (dopo circa 30 minuti) si cerca di nuovo e si riprova una volta (spec T §11):
    /// solo per una release della loro ricerca, una di Prowlarr ha il suo link.
    /// </summary>
    public async Task<GrabOutcome> GrabAsync(string key, string guid, int indexerId, CancellationToken cancellationToken, bool lighten = false) =>
        (await GrabWithRuleAsync(key, guid, indexerId, cancellationToken, lighten).ConfigureAwait(false)).Outcome;

    // Come GrabAsync. RuleRefused: il push l'ha scartata per regola (Refused, ma non è un rifiuto del client da ricordare).
    private async Task<(GrabOutcome Outcome, bool RuleRefused)> GrabWithRuleAsync(string key, string guid, int indexerId, CancellationToken cancellationToken, bool lighten)
    {
        if (!DownloadKey.TryParse(key, out var parsed) || string.IsNullOrEmpty(guid))
        {
            return (GrabOutcome.Invalid, false);
        }

        lock (_lock)
        {
            if (!_grabbing.Add(parsed.ToString()))
            {
                return (GrabOutcome.Busy, false);
            }
        }

        // Le chiavi tenute da questo grab: quella dell'admin e, per un singolo da una ricerca di stagione, quella dell'episodio.
        List<string> guarded = [parsed.ToString()];
        try
        {
            var (outcome, ruleRefused) = await GrabGuardedAsync(parsed, guid, indexerId, guarded, lighten, cancellationToken).ConfigureAwait(false);

            // "Alleggerisci" (spec U): il titolo scelto non entra negli upgrade, come dopo "va bene così".
            // Tutte le chiavi del grab: per un singolo da una ricerca di stagione anche quella dell'episodio.
            if (lighten && outcome == GrabOutcome.Ok)
            {
                var at = time.GetUtcNow();
                lock (_lock)
                {
                    guarded.ForEach(k =>
                    {
                        Book.Accept(k);
                        Book.MarkLightened(k, at);
                    });
                    SaveAfterGrab();
                }
            }

            return (outcome, ruleRefused);
        }
        finally
        {
            lock (_lock)
            {
                guarded.ForEach(k => _grabbing.Remove(k));
            }
        }
    }

    /// <summary>
    /// Come <see cref="GrabAsync"/>; se la release è rifiutata perché il torrent è già in qBittorrent, dà anche quel torrent
    /// (finito e unico con quel nome), così l'admin può importarne i file. Senza qBittorrent o senza torrent trovato è solo il rifiuto.
    /// </summary>
    public async Task<(GrabOutcome Outcome, ExistingTorrent? Existing)> GrabOrFindExistingAsync(
        string key, string guid, int indexerId, CancellationToken cancellationToken, bool lighten = false)
    {
        var started = time.GetUtcNow();
        var (outcome, ruleRefused) = await GrabWithRuleAsync(key, guid, indexerId, cancellationToken, lighten).ConfigureAwait(false);

        // Un rifiuto di regola del push non viene da qBittorrent: nessun torrent da cercare.
        return (outcome, outcome == GrabOutcome.Refused && !ruleRefused && qbit is not null ? await FindExistingAsync(qbit, started, cancellationToken).ConfigureAwait(false) : null);
    }

    // Il torrent della riga di duplicato più recente scritta da started in poi. Un errore di qBittorrent non deve nascondere il rifiuto.
    private async Task<ExistingTorrent?> FindExistingAsync(IQbitClient client, DateTimeOffset started, CancellationToken cancellationToken)
    {
        try
        {
            // Il registro ha la precisione del secondo e l'orologio di qBittorrent può essere un po' indietro.
            var from = started.ToUnixTimeSeconds() - 2;
            var name = (await client.GetLogAsync(cancellationToken).ConfigureAwait(false))
                .Where(e => e.Timestamp >= from)
                .OrderByDescending(e => e.Timestamp).ThenByDescending(e => e.Id)
                .Select(e => QbitDuplicate.NameOf(e.Message))
                .FirstOrDefault(n => n is not null);
            if (name is null)
            {
                return null;
            }

            var same = (await client.GetTorrentsAsync(cancellationToken).ConfigureAwait(false)).Where(t => t.Name == name).ToList();
            return same is [{ Progress: >= 1, Hash: { Length: > 0 } hash, ContentPath: { Length: > 0 } }] ? new ExistingTorrent(hash, name) : null;
        }
        catch (QbitException ex)
        {
            logger.LogInformation("Download automatici: qBittorrent non ha dato il torrent già presente ({Error})", ex.Error);
            return null;
        }
    }

    /// <summary>
    /// "Scarica il migliore intanto" (spec §4.1, §4.2a, §5.5): una ricerca nuova (Radarr/Sonarr scaricano solo dalla loro cache
    /// recente), la regola senza le release rifiutate dal client (§5.3), poi il tappabuchi: il migliore sotto il minimo o il più
    /// pesante tra i troppo piccoli, o il miglior 720p scartato solo per la qualità. Se nel frattempo c'è una scelta valida si
    /// scarica quella, senza tappabuchi. Una stagione prende solo il suo pack 720p. Ricerca e grab vanno fino in fondo anche se
    /// l'admin chiude la richiesta.
    /// </summary>
    public async Task<GrabOutcome> GrabBestAsync(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return GrabOutcome.Invalid;
        }

        if (!CanGrabBest(parsed))
        {
            return GrabOutcome.NothingToGrab;
        }

        var (search, error) = await ReadAsync(ServiceOf(parsed.Kind), c => RunSearchAsync(parsed, c), CancellationToken.None).ConfigureAwait(false);
        if (error is not null)
        {
            return GrabOutcome.Unavailable;
        }

        if (search is null)
        {
            return GrabOutcome.Invalid;
        }

        HashSet<string> refused;
        lock (_lock)
        {
            refused = [.. Book.Get(parsed.ToString())?.RefusedReleases ?? []];
        }

        // Come nel giro: dopo un rifiuto di regola del push la scelta successiva, fino a 3 release; poi niente da prendere.
        var ruleRefused = new HashSet<ArrRelease>();
        while (ruleRefused.Count < MaxGrabAttempts)
        {
            var releases = search.Releases.Where(r => !ruleRefused.Contains(r) && !refused.Contains(DownloadRule.ReleaseId(r.Guid ?? "", r.IndexerId)));
            ArrRelease? release;
            string? stopgap;
            if (parsed.Kind == DownloadKinds.Season)
            {
                // Una stagione: solo il pack 720p, mai singoli o altri tappabuchi (QualityPack c'è solo se il tappabuchi è Quality),
                // misurato sugli episodi della regola come nel giro. Mai se un episodio ha un file: il pack lo sostituirebbe.
                (release, stopgap) = search.RuleEpisodes is { } ruleEpisodes
                    && search.Episodes is { Count: > 0 } episodes && !episodes.Any(e => e.HasFile)
                    && SeasonPackRule.QualityPack(releases, ruleEpisodes, search.Input) is { } packs
                    ? DownloadRule.ChooseStopgap(packs)
                    : (null, null);
            }
            else
            {
                var rule = DownloadRule.Choose(releases, search.Input);
                (release, stopgap) = rule.Choice is { } choice ? (choice, null) : DownloadRule.ChooseStopgap(rule);
            }

            // Di nuovo dopo la ricerca: intanto il giro o un altro admin può aver fatto partire un download.
            if (release is null || !CanGrabBest(parsed))
            {
                return GrabOutcome.NothingToGrab;
            }

            var (outcome, byRule) = await GrabWithRuleAsync(parsed.ToString(), release.Guid!, release.IndexerId, CancellationToken.None, lighten: false).ConfigureAwait(false);
            if (byRule)
            {
                ruleRefused.Add(release);
                continue;
            }

            GrabbedBest(parsed, outcome, release, stopgap);
            return outcome;
        }

        return GrabOutcome.NothingToGrab;
    }

    // Dopo "Scarica il migliore intanto": il tappabuchi scelto, o la release rifiutata dal client.
    private void GrabbedBest(DownloadKey parsed, GrabOutcome outcome, ArrRelease release, string? stopgap)
    {
        if (outcome is GrabOutcome.Ok or GrabOutcome.Refused)
        {
            lock (_lock)
            {
                if (Book.Get(parsed.ToString()) is { } entry)
                {
                    // Una release rifiutata dal client si ricorda (spec §5.3): alla pressione dopo si prende un'altra.
                    if (outcome == GrabOutcome.Refused)
                    {
                        RememberRefused(entry, release.Guid!, release.IndexerId);
                    }
                    else
                    {
                        entry.Stopgap = stopgap;
                    }

                    SaveAfterGrab();
                }
            }
        }
    }

    // "Scarica il migliore intanto" vale solo dove la panoramica lo offre: mai su un download in corso o un upgrade.
    private bool CanGrabBest(DownloadKey key)
    {
        lock (_lock)
        {
            return Book.Get(key.ToString()) is { } entry && DownloadActions.For(entry).Contains(DownloadActions.GrabBest);
        }
    }

    /// <summary>
    /// "Va bene, aspetto" (spec §4.3): la voce torna in attesa senza avvisi, cercata una volta alla settimana. Falso se non è in
    /// <c>NeedsYou</c> per <c>NothingFound</c>.
    /// </summary>
    public bool Snooze(string key)
    {
        lock (_lock)
        {
            if (!DownloadKey.TryParse(key, out var parsed)
                || Book.Get(parsed.ToString()) is not { State: DownloadStates.NeedsYou, Reason: DownloadReasons.NothingFound } entry)
            {
                return false;
            }

            entry.State = DownloadStates.Waiting;
            entry.Snoozed = true;
            entry.RushAt = null;
            entry.NextSearchAt = time.GetUtcNow() + DownloadSchedule.SnoozedPace;
            store.Save(Book);
        }

        // Un giro presto: l'avviso esce dalla cassetta degli admin (spec §4.3).
        Nudge();
        return true;
    }

    /// <summary>
    /// "Importa comunque" (spec §4.4): lo stesso import a mano della scheda spazio. Se parte la voce torna "in download" finché
    /// Radarr/Sonarr non importano; se no resta in "Serve te" e l'errore ("NoFiles" o un codice) va all'admin.
    /// </summary>
    public async Task<(BlockedOutcome Outcome, string? Error)> ImportBlockedAsync(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return (BlockedOutcome.Invalid, null);
        }

        string downloadId;
        lock (_lock)
        {
            // Un altro import, scarto o grab della stessa chiave (doppio clic, due admin): la voce sta cambiando.
            if (Blocked(parsed) is not { DownloadId: { Length: > 0 } id } || !_grabbing.Add(parsed.ToString()))
            {
                return (BlockedOutcome.Changed, null);
            }

            downloadId = id;
        }

        try
        {
            if (await ImportDownloadAsync(ServiceOf(parsed.Kind), downloadId, CancellationToken.None).ConfigureAwait(false) is { } error)
            {
                return (BlockedOutcome.Failed, error);
            }

            lock (_lock)
            {
                // Il giro può averla cambiata intanto: si scrive solo se è ancora bloccata.
                if (Blocked(parsed) is { } entry)
                {
                    entry.State = DownloadStates.Downloading;
                    entry.Reason = null;
                    entry.AdminImportAt = time.GetUtcNow();
                    store.Save(Book);
                }
            }
        }
        finally
        {
            lock (_lock)
            {
                _grabbing.Remove(parsed.ToString());
            }
        }

        Nudge();
        return (BlockedOutcome.Ok, null);
    }

    /// <summary>
    /// Importa i file del titolo da un torrent già finito in qBittorrent (<paramref name="hash"/>), in copia: il torrent resta
    /// a seminare. Vale anche dove Sonarr li giudica peggiori di quelli in libreria. Poi la voce è accettata (il giro non cerca
    /// un upgrade) e "in download" finché il file non arriva, così il giro non lo cerca di nuovo. "NoFiles" se nel torrent non c'è niente di quel titolo.
    /// </summary>
    public async Task<(BlockedOutcome Outcome, string? Error)> ImportExistingAsync(string key, string hash, bool lighten = false)
    {
        if (!DownloadKey.TryParse(key, out var parsed) || string.IsNullOrWhiteSpace(hash))
        {
            return (BlockedOutcome.Invalid, null);
        }

        lock (_lock)
        {
            if (!_grabbing.Add(parsed.ToString()))
            {
                return (BlockedOutcome.Changed, null);
            }
        }

        try
        {
            if (qbit is null)
            {
                return (BlockedOutcome.Unavailable, null);
            }

            QbitTorrent? torrent;
            try
            {
                torrent = (await qbit.GetTorrentsAsync(CancellationToken.None).ConfigureAwait(false))
                    .FirstOrDefault(t => string.Equals(t.Hash, hash, StringComparison.OrdinalIgnoreCase));
            }
            catch (QbitException)
            {
                return (BlockedOutcome.Unavailable, null);
            }

            if (torrent is not { Progress: >= 1, ContentPath: { Length: > 0 } })
            {
                return (BlockedOutcome.Changed, null);
            }

            // Prima del comando: un file importato subito risulta più nuovo del segno di "Alleggerisci".
            var lightenedAt = time.GetUtcNow();
            var (imported, error) = await ImportFolderAsync(parsed, torrent).ConfigureAwait(false);
            if (imported is not { } files)
            {
                return (BlockedOutcome.Failed, error);
            }

            var episodes = files
                .SelectMany(f => f.Episodes?.OfType<ArrFileRef>().Where(e => e.Id > 0).Select(e => Key(DownloadKinds.Episode, e.Id)) ?? [])
                .Distinct()
                .Where(k => k != parsed.ToString())
                .ToList();
            lock (_lock)
            {
                // L'import è un comando asincrono: finché il file non c'è il titolo è ancora da scaricare, e il giro lo
                // cercherebbe di nuovo. La voce resta "in download" come dopo la scelta di un admin (GrabbedByAdmin): con il
                // file il giro la toglie (accettata), senza torna in attesa dopo lo stesso tempo di un download sparito.
                var now = time.GetUtcNow();
                var title = _lastSearch.GetValueOrDefault(parsed.ToString())?.Title;
                var entry = Book.Get(parsed.ToString()) ?? (title is null ? null : Create(title, now));
                if (entry is null)
                {
                    logger.LogWarning("Download automatici: {Key} importato senza voce né ricerca ricordata, il giro non lo segue", parsed);
                }
                else
                {
                    entry.State = DownloadStates.Downloading;
                    entry.Reason = null;
                    entry.Snoozed = false;
                    entry.Summary = null;
                    entry.LastSearchAt = now;
                    entry.QueueId = null;
                    entry.LastSizeLeft = null;
                    entry.LastProgressAt = null;
                    entry.MetadataSince = null;
                    entry.AdminImportAt = null;
                    entry.ManualImportPending = false;

                    // Numeri di un pack di prima: la stagione non intera lascerebbe agli altri episodi dei file la loro voce.
                    entry.EpisodeNumbers = null;
                    entry.Stopgap = null;
                    (entry.PreviousScore, entry.PreviousQualityId, entry.PreviousSizeBytes) = (null, null, null);
                    (entry.CurrentScore, entry.CurrentQualityId, entry.CurrentSizeBytes) = (null, null, null);
                }

                // Gli episodi dei file che aspettano o tengono d'occhio un upgrade escono (l'admin non vuole upgrade);
                // quelli che scaricano restano, così se ne continua a seguire il download.
                foreach (var episode in episodes)
                {
                    if (Book.Get(episode) is { State: DownloadStates.Waiting or DownloadStates.NeedsYou or DownloadStates.UpgradeWatch })
                    {
                        Book.Remove(episode);
                    }
                }

                // Accettati, perché il giro non cerchi un upgrade dei file importati.
                foreach (var k in episodes.Append(parsed.ToString()))
                {
                    Book.Accept(k);
                }

                // "Alleggerisci": solo la chiave del titolo, come il grab; la riga di Spazio sparisce a file importato.
                if (lighten)
                {
                    Book.MarkLightened(parsed.ToString(), lightenedAt);
                }

                SaveAfterGrab();
            }

            logger.LogInformation("Download automatici: {Key} importato da un torrent già presente, {Files} file", parsed, files.Count);
        }
        finally
        {
            lock (_lock)
            {
                _grabbing.Remove(parsed.ToString());
            }
        }

        Nudge();
        return (BlockedOutcome.Ok, null);
    }

    /// <summary>
    /// Importa in copia (il torrent resta a seminare) i file del titolo dalla cartella di un torrent finito, anche dove Sonarr li
    /// giudica peggiori di quelli in libreria. Null e il motivo ("NoFiles" o il codice dell'errore) se non riesce.
    /// </summary>
    private async Task<(List<ArrManualImportItem>? Files, string? Error)> ImportFolderAsync(DownloadKey key, QbitTorrent torrent)
    {
        var service = ServiceOf(key.Kind);
        try
        {
            var files = OnePerTitle(
                service,
                [.. (await arr.GetManualImportByFolderAsync(service, torrent.ContentPath!, CancellationToken.None).ConfigureAwait(false))
                    .OfType<ArrManualImportItem>().Where(i => Importable(service, i) && IsOfTitle(key, i))]);
            if (files.Count == 0)
            {
                return (null, "NoFiles");
            }

            // Token mai annullato: il lavoro deve finire anche se l'app si chiude. Copia: il torrent deve restare a seminare.
            await arr.ManualImportAsync(service, files, CancellationToken.None, copy: true).ConfigureAwait(false);
            return (files, null);
        }
        catch (Exception ex)
        {
            return (null, ErrorOf(ex));
        }
    }

    // Un file del titolo della chiave: il film; l'episodio tra quelli del file; la serie e la stagione.
    private static bool IsOfTitle(DownloadKey key, ArrManualImportItem item) => key.Kind switch
    {
        DownloadKinds.Movie => item.Movie?.Id == key.Id,
        DownloadKinds.Episode => item.Episodes?.Any(e => e?.Id == key.Id) == true,
        _ => item.Series?.Id == key.Id && item.SeasonNumber == key.Season,
    };

    /// <summary>
    /// "Scarta e cerca un altro" (spec §4.4): il download esce dalla coda e dal client con la blocklist, poi una ricerca subito.
    /// La voce torna in attesa, o a tenere d'occhio l'upgrade con il file di prima. Vale per un import bloccato e per un
    /// download fermo sui metadati (<see cref="DownloadEntry.MetadataSince"/>), che si scarta senza aspettare le ore della soglia.
    /// </summary>
    public async Task<BlockedOutcome> DiscardBlockedAsync(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return BlockedOutcome.Invalid;
        }

        string? downloadId;
        lock (_lock)
        {
            // Come per l'import: una seconda azione sulla stessa chiave trova la voce che cambia.
            if (Discardable(parsed) is not { } discarded || !_grabbing.Add(parsed.ToString()))
            {
                return BlockedOutcome.Changed;
            }

            downloadId = discarded.DownloadId;
        }

        try
        {
            if (!await RemoveOldDownloadAsync(parsed, ServiceOf(parsed.Kind), CancellationToken.None, blocklist: true, downloadId).ConfigureAwait(false))
            {
                return BlockedOutcome.Unavailable;
            }

            lock (_lock)
            {
                if (Discardable(parsed) is { } entry)
                {
                    var now = time.GetUtcNow();
                    if (entry.PreviousScore is not null)
                    {
                        BackToUpgradeWatch(entry, now);
                    }
                    else
                    {
                        BackToWaiting(entry, now);
                    }

                    entry.NextSearchAt = now;
                    entry.DownloadId = null;
                    entry.BlockedMessage = null;
                    store.Save(Book);
                }
            }
        }
        finally
        {
            lock (_lock)
            {
                _grabbing.Remove(parsed.ToString());
            }
        }

        Nudge();
        return BlockedOutcome.Ok;
    }

    // Solo sotto _lock. La voce ferma perché Radarr/Sonarr non importano; null in un altro stato.
    private DownloadEntry? Blocked(DownloadKey key) =>
        Book.Get(key.ToString()) is { State: DownloadStates.NeedsYou, Reason: DownloadReasons.ImportBlocked } entry ? entry : null;

    // Solo sotto _lock. La voce che "Scarta" può togliere: bloccata sull'import, o ferma sui metadati; null in un altro stato.
    private DownloadEntry? Discardable(DownloadKey key) =>
        Blocked(key) ?? (Book.Get(key.ToString()) is { State: DownloadStates.Downloading, MetadataSince: not null } entry ? entry : null);

    /// <summary>I grab di "Alleggerisci" ancora ricordati, per la scheda spazio: una copia.</summary>
    public IReadOnlyDictionary<string, DateTimeOffset> LightenedKeys()
    {
        lock (_lock)
        {
            return new Dictionary<string, DateTimeOffset>(Book.Lightened);
        }
    }

    /// <summary>Dimentica un grab di "Alleggerisci" (importato o troppo vecchio).</summary>
    public void ForgetLightened(string key)
    {
        lock (_lock)
        {
            if (Book.ForgetLightened(key))
            {
                SaveAfterGrab();
            }
        }
    }

    /// <summary>
    /// Prima di un import a mano dalla scheda spazio: il giro non manda un secondo ManualImport per lo stesso grab. Toglie
    /// ManualImportPending alla chiave e alle altre segnate dallo stesso "Alleggerisci" (stessa ora, per esempio l'episodio).
    /// </summary>
    public void SkipManualImport(string key)
    {
        lock (_lock)
        {
            if (!Book.Lightened.TryGetValue(key, out var at))
            {
                return;
            }

            var changed = false;
            foreach (var entry in Book.Lightened.Where(p => p.Value == at).Select(p => Book.Get(p.Key)).OfType<DownloadEntry>().Where(e => e.ManualImportPending))
            {
                entry.ManualImportPending = false;
                changed = true;
            }

            if (changed)
            {
                SaveAfterGrab();
            }
        }
    }

    private async Task<(GrabOutcome Outcome, bool RuleRefused)> GrabGuardedAsync(
        DownloadKey parsed, string guid, int indexerId, List<string> guarded, bool lighten, CancellationToken cancellationToken)
    {
        var service = ServiceOf(parsed.Kind);
        AdminSearch? search;

        // La ricerca di nuovo: con il motore del job dell'admin (Prowlarr senza job), o dopo risultati scaduti con Radarr/Sonarr.
        SearchEngine engine;
        lock (_lock)
        {
            search = _lastSearch.GetValueOrDefault(parsed.ToString());
            engine = _searchJobs.TryGetValue(parsed.ToString(), out var job) ? job.Engine : SearchEngine.Prowlarr;
        }

        var searchedAgain = false;
        var oldRemoved = false;

        // "cambia": c'era un download di prima, ed è stato tolto.
        var replaced = false;
        while (true)
        {
            if (search is null || search.Releases.FirstOrDefault(r => r.Guid == guid && r.IndexerId == indexerId) is not { } release)
            {
                if (searchedAgain)
                {
                    return (GrabOutcome.Expired, false);
                }

                var (fresh, error) = await ReadAsync(service, c => RunSearchAsync(parsed, c, engine: engine), cancellationToken).ConfigureAwait(false);
                if (error is not null)
                {
                    return (GrabOutcome.Unavailable, false);
                }

                if (fresh is null)
                {
                    return (GrabOutcome.Invalid, false);
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
                        return (GrabOutcome.Busy, false);
                    }
                }

                guarded.Add(target.Title.Key);
            }

            if (!oldRemoved)
            {
                lock (_lock)
                {
                    replaced = HasOldDownload(parsed.ToString()) || (target.Title.Key != parsed.ToString() && HasOldDownload(target.Title.Key));
                }
            }

            if (!oldRemoved
                && (!await RemoveOldDownloadAsync(parsed, service, cancellationToken).ConfigureAwait(false)
                    || (target.Title.Key != parsed.ToString()
                        && DownloadKey.TryParse(target.Title.Key, out var episode)
                        && !await RemoveOldDownloadAsync(episode, service, cancellationToken).ConfigureAwait(false))))
            {
                return (GrabOutcome.Unavailable, false);
            }

            oldRemoved = true;

            // Un download voluto (Alleggerisci, un file che Radarr/Sonarr non sostituirebbero, qualcosa che non seguono, una qualità
            // fuori dal profilo): se il push lo scarta solo per file, coda, monitoraggio o qualità va direttamente in qBittorrent.
            var intentional = lighten || (target.Current is not null && !WouldImport(search.Profile, target.Current, release)) || !target.Monitored
                || (search.Profile is { } profile && release.Quality?.Quality is { } quality && !DownloadRule.IsAllowed(profile, quality.Id));
            GrabResult result;
            try
            {
                result = await _finder.GrabAsync(service, release, intentional, cancellationToken).ConfigureAwait(false);
                if (result.Kind == GrabKind.RuleRefused && replaced)
                {
                    // Il download di prima è già tolto: l'admin non resta senza niente, il torrent va direttamente in qBittorrent.
                    logger.LogInformation("Download automatici: {Key}, {Kind} ha rifiutato per regola la release dell'admin ({Reason}): aggiunta direttamente a qBittorrent", search.Title.Key, service, result.Reason);
                    result = new GrabResult(GrabKind.Direct, null, await _finder.AddDirectAsync(service, release, cancellationToken).ConfigureAwait(false));
                }
            }
            catch (ArrException ex) when ((ex.Status is 404 or 400) && release.Source == ReleaseSource.Arr)
            {
                // Risultati scaduti in Radarr/Sonarr: una nuova ricerca con loro, se non è già quella di adesso.
                if (searchedAgain)
                {
                    return (GrabOutcome.Expired, false);
                }

                (search, engine) = (null, SearchEngine.Arr);
                continue;
            }
            catch (ArrException ex) when (ex.Status >= 500)
            {
                // Radarr/Sonarr hanno risposto: non è un servizio che non risponde (spec T §8.2).
                logger.LogWarning("Download automatici: {Key}, {Kind} ha rifiutato la release dell'admin ({Error})", search.Title.Key, service, ErrorOf(ex));
                return (GrabOutcome.Refused, false);
            }
            catch (QbitException ex) when (ex.Error == QbitError.Refused && !cancellationToken.IsCancellationRequested)
            {
                // qBittorrent non ha preso il torrent (spesso perché c'è già): un rifiuto, così si cerca il torrent esistente.
                logger.LogWarning("Download automatici: {Key}, qBittorrent ha rifiutato la release dell'admin", search.Title.Key);
                return (GrabOutcome.Refused, false);
            }
            catch (QbitException ex) when (!cancellationToken.IsCancellationRequested)
            {
                // qBittorrent giù o lento: non è un rifiuto della release ("Scarica il migliore" non la scarta).
                logger.LogWarning("Download automatici: {Key}, qBittorrent non ha preso la release dell'admin ({Error})", search.Title.Key, ex.Error);
                return (GrabOutcome.Unavailable, false);
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning("Download automatici: {Key}, {Kind} non ha scaricato la release dell'admin ({Error})", search.Title.Key, service, ErrorOf(ex));
                return (GrabOutcome.Unavailable, false);
            }

            if (result.Kind is GrabKind.RuleRefused or GrabKind.ClientRefused)
            {
                // Il motivo è di Sonarr/Radarr, mai il titolo.
                logger.LogWarning("Download automatici: {Key}, {Kind} ha rifiutato la release dell'admin ({Reason})", search.Title.Key, service, result.Reason ?? result.Kind.ToString());
                return (GrabOutcome.Refused, result.Kind == GrabKind.RuleRefused);
            }

            logger.LogInformation("Download automatici: {Key} scaricato da {Kind} per l'admin", target.Title.Key, service);
            GrabbedByAdmin(search, target, release, result.Kind == GrabKind.Direct ? result.Hash : null);

            // Un giro presto: la voce "serve te" di questo titolo esce dalla cassetta degli admin (spec V).
            Nudge();
            return (GrabOutcome.Ok, false);
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

    // Solo sotto _lock. Una riga che manca davvero: niente UpgradeWatch (il file c'è già) né import bloccato.
    private bool CanRush(DownloadEntry entry) => entry.State != DownloadStates.UpgradeWatch && SearchesByState(entry);

    /// <summary>
    /// "Scarica subito": il film, o tutte le righe della serie che mancano, passano davanti nella coda del giro (RushAt) e il giro
    /// in corso si ferma dopo la ricerca che sta facendo. Falso se la chiave non ha una voce; vero anche senza righe da anticipare.
    /// </summary>
    public bool Rush(string key)
    {
        lock (_lock)
        {
            if (!DownloadKey.TryParse(key, out var parsed) || Book.Get(parsed.ToString()) is not { } entry)
            {
                return false;
            }

            // Un libro vecchio può avere SeriesId 0: allora solo la voce stessa, non tutte quelle con 0.
            IEnumerable<DownloadEntry> rows = entry.Kind == DownloadKinds.Movie || entry.SeriesId == 0
                ? [entry]
                : Book.Entries.Where(e => e.SeriesId == entry.SeriesId && e.Kind != DownloadKinds.Movie);
            var now = time.GetUtcNow();
            var touched = false;
            foreach (var row in rows.Where(CanRush))
            {
                row.RushAt ??= now;
                row.NextSearchAt = now;
                touched = true;
            }

            if (!touched)
            {
                return true;
            }

            _rushRequested = true;
            store.Save(Book);
        }

        Nudge();
        return true;
    }

    /// <summary>
    /// "Aggiorna ora": il giro in corso si ferma dopo la ricerca che sta facendo e ne riparte uno che rilegge Sonarr e Radarr
    /// senza cercare (salvo righe con la precedenza). <see cref="DownloadsOverviewDto.RefreshPending"/> resta vero finché non l'ha fatto.
    /// </summary>
    public void Refresh()
    {
        lock (_lock)
        {
            _rushRequested = _refreshPending = true;
        }

        Nudge();
    }

    /// <summary>Un giro urgente è chiesto e non è ancora partito: il servizio in background non aspetta il minuto normale.</summary>
    public bool UrgentCycleWanted
    {
        get
        {
            lock (_lock)
            {
                return _rushRequested;
            }
        }
    }

    /// <summary>
    /// "Cerca un upgrade" da "Da ripassare": il titolo torna in UpgradeWatch per <see cref="DownloadSchedule.UpgradeWindow"/>,
    /// cercato al prossimo giro, chiesto subito. Con una voce che si cerca già è "Cerca adesso".
    /// </summary>
    public HuntOutcome Hunt(string key)
    {
        if (!DownloadKey.TryParse(key, out var parsed))
        {
            return HuntOutcome.Invalid;
        }

        var normalized = parsed.ToString();
        lock (_lock)
        {
            var now = time.GetUtcNow();
            if (Book.Get(normalized) is { } existing)
            {
                if (!SearchesByState(existing))
                {
                    return HuntOutcome.Changed;
                }

                existing.NextSearchAt = now;
            }
            else
            {
                if (Book.Review.FirstOrDefault(r => r.Key == normalized) is not { } item || !CanHunt(item))
                {
                    return HuntOutcome.Changed;
                }

                Book.Put(new DownloadEntry
                {
                    Key = normalized,
                    Kind = item.Kind,
                    Title = item.Title,
                    PosterUrl = item.PosterUrl,
                    State = DownloadStates.UpgradeWatch,
                    AvailableSince = now,
                    NextSearchAt = now,
                    UpgradeUntil = now + DownloadSchedule.UpgradeWindow,
                    CurrentScore = item.Score,
                    CurrentQualityId = item.QualityId,
                    CurrentSizeBytes = item.SizeBytes,
                    ProfileId = item.ProfileId,
                    RuntimeMinutes = item.RuntimeMinutes,
                    SeriesId = parsed.Kind == DownloadKinds.Season ? parsed.Id : 0,
                    EpisodeNumbers = item.EpisodeNumbers is { } numbers ? [.. numbers] : null,
                });
                Book.RemoveFromReview(normalized);
            }

            store.Save(Book);
        }

        Nudge();
        return HuntOutcome.Ok;
    }

    // Solo sotto _lock. Senza qualità WouldImport accetterebbe una qualità più bassa; senza episodi una stagione non si cerca;
    // un titolo non monitorato il giro lo toglie prima di cercarlo; uno accettato non ha upgrade.
    private bool CanHunt(ReviewItem item) =>
        item.Monitored
        && item.QualityId is not null
        && (item.Kind != DownloadKinds.Season || item.EpisodeNumbers is { Count: > 0 })
        && !Book.IsAccepted(item.Key);

    /// <summary>
    /// La panoramica (spec T §8.1): scelte dalla più recente, voci seguite, "Da ripassare", errori dell'ultimo giro, tutto dal libro;
    /// l'avanzamento di chi scarica viene dalla coda di Radarr/Sonarr (una lettura al minuto, mai bloccante: se fallisce resta vuoto).
    /// </summary>
    public async Task<DownloadsOverviewDto> OverviewAsync(CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var since = now - DownloadBook.ChoiceRetention;
        DownloadsOverviewDto overview;
        Dictionary<string, DateTimeOffset> metadataSince;
        lock (_lock)
        {
            metadataSince = Book.Entries.Where(e => e.MetadataSince is not null).ToDictionary(e => e.Key, e => e.MetadataSince!.Value);
            // Prune gira solo a fine giro: le scelte vecchie si filtrano anche qui.
            overview = new DownloadsOverviewDto(
                settings.Enabled,
                [.. Book.Choices.Where(c => c.At >= since).Select(ChoiceDto)],
                [.. Book.Entries
                    .Where(e => e.State is DownloadStates.Waiting or DownloadStates.NeedsYou or DownloadStates.Downloading or DownloadStates.UpgradeWatch)
                    .OrderBy(e => e.NextSearchAt)
                    .Select(e => ItemDto(e, now))],
                [.. Book.Review
                    .Where(r => !Book.IsAccepted(r.Key))
                    .Select(r => new ReviewItemDto(r.Key, r.Kind, r.Title, r.PosterUrl, r.Score, r.SizeBytes, r.Quality, CanHunt(r)))],
                Book.ReviewAt,
                _lastErrors.Sonarr,
                _lastErrors.Radarr,
                [],
                SearchProgress(now),
                _refreshPending);
        }

        // Fuori dal lock: la coda solo dei servizi che hanno qualcuno in download.
        var kinds = overview.Waiting.Where(i => i.State == DownloadStates.Downloading).Select(i => ServiceOf(i.Kind)).Distinct().ToList();
        var queues = new Dictionary<ArrKind, IReadOnlyDictionary<string, DownloadProgressDto>>();
        foreach (var kind in kinds)
        {
            var read = await _queues.GetAsync(kind.ToString(), () => ReadProgressAsync(kind)).WaitAsync(cancellationToken).ConfigureAwait(false);
            if (read.Value is { } progress)
            {
                queues[kind] = progress;
            }
        }

        var unknown = await UnknownAsync(cancellationToken).ConfigureAwait(false);
        return overview with
        {
            Waiting = [.. overview.Waiting.Select(i => i.State == DownloadStates.Downloading && queues.GetValueOrDefault(ServiceOf(i.Kind)) is { } p
                ? i with { Progress = WithSince(p.GetValueOrDefault(i.Key), metadataSince.GetValueOrDefault(i.Key)) }
                : i)],
            Unknown = unknown,
        };
    }

    // Un servizio che non risponde lo dicono già gli errori del giro: qui resta vuoto. Uno lento non ferma la panoramica:
    // allo scadere la sezione è vuota e la lettura, che non si cancella, finisce in cache per il poll dopo.
    private async Task<IReadOnlyList<UnknownDownloadDto>> UnknownAsync(CancellationToken cancellationToken)
    {
        var reads = Enum.GetValues<ArrKind>()
            .Where(k => arrSettings.Endpoint(k).IsConfigured)
            .Select(k => _unknown.GetAsync(k.ToString(), () => ReadUnknownAsync(k)))
            .ToList();
        try
        {
            var done = await Task.WhenAll(reads).WaitAsync(UnknownReadLimit, time, cancellationToken).ConfigureAwait(false);
            return [.. done.SelectMany(r => r.Value ?? [])];
        }
        catch (TimeoutException)
        {
            return [];
        }
    }

    private async Task<IReadOnlyList<UnknownDownloadDto>> ReadUnknownAsync(ArrKind kind)
    {
        var queue = await arr.GetUnknownQueueAsync(kind, CancellationToken.None).ConfigureAwait(false);
        return [.. UnknownDownloads(queue).Select(d => new UnknownDownloadDto(kind.ToString(), d.Key, d.First().Title ?? d.Key, d.First().Size, StatusMessageOf(d)))];
    }

    // Per DownloadId i download senza titolo e fermi all'import. Togliendone uno si cancellano i file: se anche un solo elemento
    // dello stesso torrent è legato a un titolo, o non è fermo, il download non è di questi. Nemmeno i torrent messi da noi in
    // qBittorrent (DirectGrabs): per Sonarr/Radarr sono senza titolo, ma li importa il giro.
    private IEnumerable<IGrouping<string, ArrQueueItem>> UnknownDownloads(IEnumerable<ArrQueueItem?> queue)
    {
        HashSet<string> direct;
        lock (_lock)
        {
            direct = new(Book.DirectGrabs.Keys, StringComparer.OrdinalIgnoreCase);
        }

        return queue.OfType<ArrQueueItem>()
            .Where(q => !string.IsNullOrEmpty(q.DownloadId) && !direct.Contains(q.DownloadId))
            .GroupBy(q => q.DownloadId!)
            .Where(d => d.All(q => q.Id > 0 && !HasTitle(q) && IsImportBlocked(q)));
    }

    private static bool HasTitle(ArrQueueItem item) => item.SeriesId > 0 || item.EpisodeId > 0 || item.MovieId > 0;

    /// <summary>
    /// "Rimuovi" su un download senza titolo: rilegge la coda dal vivo e toglie il download dal client, file compresi, senza blocklist.
    /// Invalid per una richiesta non valida, Changed se non è più senza titolo e fermo o se ha un titolo nell'altro servizio,
    /// Unavailable se Radarr/Sonarr non rispondono (anche solo l'altro, se è configurato).
    /// </summary>
    public async Task<BlockedOutcome> RemoveUnknownAsync(string? service, string? downloadId)
    {
        if (service is not (nameof(ArrKind.Sonarr) or nameof(ArrKind.Radarr)) || string.IsNullOrWhiteSpace(downloadId))
        {
            return BlockedOutcome.Invalid;
        }

        var kind = service == nameof(ArrKind.Radarr) ? ArrKind.Radarr : ArrKind.Sonarr;
        try
        {
            var queue = await arr.GetUnknownQueueAsync(kind, CancellationToken.None).ConfigureAwait(false);
            if (UnknownDownloads(queue).FirstOrDefault(d => d.Key == downloadId) is not { } download)
            {
                return BlockedOutcome.Changed;
            }

            // Con una categoria di qBittorrent condivisa, un film legato in Radarr compare in Sonarr senza serie: stessi file.
            var other = kind == ArrKind.Radarr ? ArrKind.Sonarr : ArrKind.Radarr;
            if (arrSettings.Endpoint(other).IsConfigured
                && (await arr.GetQueueAsync(other, CancellationToken.None).ConfigureAwait(false))
                    .OfType<ArrQueueItem>()
                    .Any(q => HasTitle(q) && string.Equals(q.DownloadId, downloadId, StringComparison.OrdinalIgnoreCase)))
            {
                return BlockedOutcome.Changed;
            }

            var removed = false;
            foreach (var item in download)
            {
                try
                {
                    await arr.RemoveFromQueueAsync(kind, item.Id, blocklist: false, removeFromClient: true, CancellationToken.None).ConfigureAwait(false);
                    removed = true;
                }
                catch (ArrException ex) when (ex.Status == 404)
                {
                    // Già tolto, o insieme al torrent di un altro elemento.
                }
                catch (Exception ex) when (removed)
                {
                    // Il primo tolto si porta via il torrent: gli altri elementi possono non esserci più.
                    logger.LogWarning("Download senza titolo: {Kind} non ha tolto un elemento ({Error})", kind, ErrorOf(ex));
                }
            }

            logger.LogInformation("Download senza titolo: {Title} tolto da {Kind}", download.First().Title, kind);
        }
        catch (Exception ex)
        {
            logger.LogWarning("Download senza titolo: {Kind} non ha tolto il download ({Error})", kind, ErrorOf(ex));
            return BlockedOutcome.Unavailable;
        }
        finally
        {
            // Anche se è cambiato: la riga vecchia non deve restare in elenco per un minuto.
            _unknown.Forget(kind.ToString());
        }

        return BlockedOutcome.Ok;
    }

    // "metadata" dice da quando lo è la voce (la lettura della coda in cache non lo sa); altrimenti l'avanzamento com'è.
    private static DownloadProgressDto? WithSince(DownloadProgressDto? progress, DateTimeOffset since) =>
        progress is { Status: MetadataStatus } ? progress with { Since = since == default ? null : since } : progress;

    // La coda di un servizio come avanzamento per chiave, con le stesse regole del giro. Non ha il token di chi chiede: la lettura è condivisa dalla cache.
    private async Task<IReadOnlyDictionary<string, DownloadProgressDto>> ReadProgressAsync(ArrKind kind)
    {
        var records = (await arr.GetQueueAsync(kind, CancellationToken.None).ConfigureAwait(false)).OfType<ArrQueueItem>().ToList();
        var groups = kind == ArrKind.Radarr
            ? ByKey(records.Where(q => q.MovieId > 0), q => Key(DownloadKinds.Movie, q.MovieId!.Value)).ToDictionary(p => p.Key, p => (IReadOnlyList<ArrQueueItem>)[p.Value])
            : ByKey(records.Where(q => q.EpisodeId > 0), q => Key(DownloadKinds.Episode, q.EpisodeId!.Value)).ToDictionary(p => p.Key, p => (IReadOnlyList<ArrQueueItem>)[p.Value])
                .Concat(SeasonQueueOf(records)).ToDictionary(p => p.Key, p => p.Value);
        return groups.ToDictionary(p => p.Key, p => ProgressOf(p.Value));
    }

    // Un pack ha un elemento per episodio col peso di tutto il download: si conta una volta per DownloadId (come SpaceService.FromQueue).
    private static DownloadProgressDto ProgressOf(IReadOnlyList<ArrQueueItem> items)
    {
        var downloads = items.Where(i => i.DownloadId is null).Concat(items.Where(i => i.DownloadId is not null).DistinctBy(i => i.DownloadId)).ToList();
        var status = items.Any(IsFetchingMetadata)
            ? MetadataStatus
            : items.FirstOrDefault(i => string.Equals(i.Status, DownloadingState, StringComparison.OrdinalIgnoreCase))?.Status ?? items[0].Status;
        return new DownloadProgressDto(downloads.Sum(i => i.Size), downloads.Sum(i => i.Sizeleft), items.Max(i => i.EstimatedCompletionTime), status ?? "unknown");
    }

    // Il messaggio di Sonarr/Radarr esce solo per un import bloccato: su una voce passata ad altro può restarne uno vecchio.
    // La fase solo sotto _lock (come ItemDto): in ricerca adesso, o in coda per il prossimo giro.
    // Il link esterno solo con l'azione ExternalSearch.
    private DownloadItemDto ItemDto(DownloadEntry e, DateTimeOffset now)
    {
        var external = DownloadActions.OffersExternalSearch(e) ? ExternalSearch.UrlFor(settings.ExternalSearchUrl, e.Title) : null;
        return new(
            e.Key, e.Kind, e.Title, e.PosterUrl, e.State, e.Reason, e.AvailableSince, e.LastSearchAt, e.NextSearchAt,
            DownloadActions.For(e, external),
            e.Summary is { } s ? new DownloadSummaryDto(s.Found, s.BestScore, s.MinScore, s.TooSmall, s.ArrRejected, s.TopRejection, s.StopgapAvailable) : null,
            e.Reason == DownloadReasons.ImportBlocked ? e.BlockedMessage : null,
            e.Snoozed,
            null,
            _searching.ContainsKey(e.Key) || AdminSearching(e.Key) ? DownloadSearchPhases.Searching
                : settings.Enabled && e.NextSearchAt <= now && SearchesByState(e) ? DownloadSearchPhases.Queued
                : null,
            external,
            e.SeriesId > 0 ? e.SeriesId : null,
            CanRush(e),
            e.RushAt is not null && CanRush(e));
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

    // Fuori dal lock: titolo, file, profilo e release, poi la regola; la ricerca si ricorda per il grab. Solo da RunSearchAsync.
    private async Task<AdminSearch?> SearchForAdminAsync(DownloadKey key, SearchEngine engine, CancellationToken cancellationToken)
    {
        if (await ReadTargetAsync(key, cancellationToken).ConfigureAwait(false) is not { } target)
        {
            return null;
        }

        var service = ServiceOf(key.Kind);
        var context = await ReadContextAsync(service)(cancellationToken).ConfigureAwait(false);
        var found = await _finder.SearchAsync(key, engine, cancellationToken).ConfigureAwait(false);
        var releases = found.Releases.OfType<ArrRelease>().ToList();
        var files = target.Files is { } check ? await CurrentFilesAsync(check, cancellationToken).ConfigureAwait(false) : [];
        var current = CurrentOf(files);

        var title = target.Title;
        var profile = context.Profiles.GetValueOrDefault(title.ProfileId);
        var thresholds = settings.For(service, title.ProfileId, profile?.Name);
        var checks = context.Checks is { } all ? ChecksFor(all, service, service == ArrKind.Radarr ? key.Id : title.SeriesId, title.Tags ?? [], profile) : null;
        var input = new RuleInput(title.RuntimeMinutes, service == ArrKind.Radarr, settings.MinGbPerHour, thresholds.MinScore, context.IndexerPriority, checks);
        var (rule, choice) = ApplyRule(releases, input, target.RuleEpisodes);
        var result = new DownloadSearchDto(
            title.Key,
            title.Kind,
            title.Title,
            title.RuntimeMinutes,
            current is null ? null : new DownloadCurrentFileDto(current.SizeBytes, current.Score, current.Quality),
            [.. rule.Candidates.Select((r, i) => new DownloadCandidateDto(i + 1, ReleaseDto(r), ReferenceEquals(r, choice), WouldImport(profile, current, r)))],
            [.. rule.Rejected.Select(r => new DownloadRejectedDto(ReleaseDto(r.Release), r.Reason, r.Detail)),
                .. found.WrongTitle.Select(r => new DownloadRejectedDto(ReleaseDto(r), "WrongTitle", r.WrongTitle))],
            rule.Candidates.Count,
            releases.Count(r => !string.IsNullOrEmpty(r.Guid)),
            null,
            choice is null ? EpisodeChoicesOf(target, releases, files, input, thresholds.TargetScore, profile, time.GetUtcNow()) : [],
            ExternalSearch.UrlFor(settings.ExternalSearchUrl, title.Title),
            found.Engine.ToString(),

            // "Trovato poco" (spec ricerche-prowlarr §7): niente di valido o, per una stagione, nessun pack completo.
            rule.Candidates.Count == 0 || (key.Kind == DownloadKinds.Season && !rule.Candidates.Any(r => r.FullSeason)));

        var search = new AdminSearch(title, current, profile, target.SeasonEpisodes, releases, result, time.GetUtcNow(), target.Episodes, files, input, target.RuleEpisodes);
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

            // Il push scarta anche un episodio di una serie non monitorata.
            var title = EpisodeTitleOf(episode, now) with { Monitored = episode.Monitored && episode.Series?.Monitored != false };
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
            SeriesId: show.Id,
            Tags: show.Tags);
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
            return new GrabTarget(search.Title, search.Current, null, search.Title.Monitored);
        }

        var partial = !release.FullSeason && release.SeasonEpisodeNumbers is { Count: > 0 };
        List<int> numbers = partial ? [.. release.SeasonEpisodeNumbers!] : [.. all];
        var covered = episodes.Where(e => numbers.Contains(e.EpisodeNumber)).ToList();
        var fileIds = covered.Select(e => e.EpisodeFileId).Where(id => id > 0).ToHashSet();
        var current = CurrentOf([.. search.Files.Where(f => fileIds.Contains(f.Id))]);
        var monitored = covered.All(e => e.Monitored && e.Series?.Monitored != false);
        return partial && numbers is [_] && covered is [var episode]
            ? new GrabTarget(EpisodeTitleOf(episode, now), current, null, monitored)
            : new GrabTarget(search.Title, current, numbers, monitored);
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
            var episodes = release.FullSeason ? seasonEpisodes.Count : Math.Max(1, release.SeasonEpisodeNumbers?.Count ?? 0);
            var one = DownloadRule.Choose([release], input with { RuntimeMinutes = minutes * episodes, EpisodeMinutes = minutes });
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
        var singles = releases.Where(r => !r.FullSeason && r.SeasonEpisodeNumbers is { Count: 1 }).ToLookup(r => r.SeasonEpisodeNumbers![0]);
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

    // "cambia" (spec T §8.2): tutto quello che il titolo ha in coda si toglie, anche dal client, senza blocklist ("Scarta" con);
    // anche un download fermo in "Serve te" o appena scelto (QueueId non ancora letto). Falso se non si è potuto.
    // Con downloadId si toglie solo quel download: una stagione può averne altri sani ("Scarta").
    private async Task<bool> RemoveOldDownloadAsync(DownloadKey key, ArrKind service, CancellationToken cancellationToken, bool blocklist = false, string? downloadId = null)
    {
        string? direct;
        lock (_lock)
        {
            if (!HasOldDownload(key.ToString()))
            {
                return true;
            }

            direct = downloadId is null ? Book.Get(key.ToString())?.DirectHash : null;
        }

        try
        {
            var queue = (await arr.GetQueueAsync(service, cancellationToken).ConfigureAwait(false)).OfType<ArrQueueItem>()
                .Where(q => downloadId is null || q.DownloadId == downloadId);
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
                    await arr.RemoveFromQueueAsync(service, ids[i], blocklist, removeFromClient: true, cancellationToken).ConfigureAwait(false);
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

        if (direct is not null)
        {
            await RemoveDirectAsync(key.ToString(), direct, cancellationToken).ConfigureAwait(false);
        }

        return true;
    }

    // Il torrent di prima messo da noi in qBittorrent si toglie, con i file, come la coda toglie i suoi dal client. Un errore di
    // qBittorrent non ferma il grab nuovo: il torrent resta, non più seguito (compare fra i download senza titolo).
    private async Task RemoveDirectAsync(string key, string hash, CancellationToken cancellationToken)
    {
        try
        {
            if (qbit is not null)
            {
                await qbit.DeleteAsync([hash], deleteFiles: true, cancellationToken).ConfigureAwait(false);
            }
        }
        catch (QbitException ex)
        {
            logger.LogWarning("Download automatici: {Key}, qBittorrent non ha tolto il torrent diretto di prima ({Error})", key, ex.Error);
        }

        lock (_lock)
        {
            Book.DirectGrabs.Remove(hash);
            if (Book.Get(key) is { } entry && entry.DirectHash == hash)
            {
                entry.DirectHash = null;
            }
        }
    }

    // Solo sotto _lock. La voce ha un download da togliere prima di un altro: in coda, o appena scelto (QueueId non ancora letto).
    private bool HasOldDownload(string key) => Book.Get(key) is { } entry && (entry.QueueId is not null || entry.State == DownloadStates.Downloading);

    // Dopo un grab riuscito: la voce (creata se manca, per esempio da "Da ripassare") scarica la scelta dell'admin.
    // Con un file presente è un upgrade, che il giro conferma dal file (ruling 5-6); se Radarr/Sonarr non lo
    // importerebbero si importa a mano (decisione 9). DirectHash: il torrent messo da noi in qBittorrent, che segue ApplyDirect.
    private void GrabbedByAdmin(AdminSearch search, GrabTarget target, ArrRelease release, string? directHash)
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
            // Un torrent nostro di prima non si segue più.
            if (entry.DirectHash is { } old && old != directHash && Book.DirectGrabs.GetValueOrDefault(old) == entry.Key)
            {
                Book.DirectGrabs.Remove(old);
            }

            entry.DirectHash = directHash;
            if (directHash is not null)
            {
                Book.DirectGrabs[directHash] = entry.Key;
            }

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
            SaveAfterGrab();
        }
    }

    // Solo sotto _lock. Il grab in Radarr/Sonarr è già fatto: un disco che non scrive non deve farlo sembrare fallito (un 500).
    private void SaveAfterGrab()
    {
        try
        {
            store.Save(Book);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning("Download automatici: non riesco a salvare il file dopo un grab ({Error})", ex.GetType().Name);
        }
    }

    private static DownloadReleaseDto ReleaseDto(ArrRelease r) =>
        new(r.Guid ?? "", r.IndexerId, r.Indexer ?? "", r.Title ?? "", r.Quality?.Quality?.Name ?? "", r.Quality?.Quality?.Resolution ?? 0, r.Size, r.CustomFormatScore, r.Seeders, r.FullSeason);

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
