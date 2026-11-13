using System.Globalization;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Il giro, seconda parte (spec T §5): la ricerca dei titoli che mancano, la scelta con la regola, gli upgrade.</summary>
public sealed partial class DownloadService
{
    // Letti una volta per giro e servizio: i profili per id e la priorità di ogni indexer. Con Prowlarr anche quello che serve
    // a scartare le sue release (Checks, senza profilo né tag, con la blocklist di tutti i titoli).
    private sealed record SearchContext(IReadOnlyDictionary<int, ArrQualityProfile> Profiles, IReadOnlyDictionary<int, int> IndexerPriority, ChecksContext? Checks = null);

    // Una voce da cercare, copiata sotto il lock. TitleId: la serie (Sonarr) o il film (Radarr), per la blocklist; Tags: i suoi tag.
    // Solo stagioni: i numeri degli episodi per il pack e le voci in cui si divide.
    private sealed record SearchItem(
        string Key,
        ArrKind Service,
        DownloadKey Target,
        bool Upgrade,
        int ProfileId,
        int RuntimeMinutes,
        int? CurrentScore,
        int? CurrentQualityId,
        IReadOnlySet<string> Refused,
        string? Stopgap,
        int TitleId,
        IReadOnlyList<int> Tags,
        IReadOnlyList<int>? Episodes = null,
        IReadOnlyList<ArrTitle>? SplitInto = null,
        bool SeasonNoFiles = false);

    // Quante release rifiutate dal client si ricordano per voce.
    private const int MaxRefusedReleases = 20;

    // Quante release si provano al massimo in una ricerca quando il push le rifiuta per regola.
    private const int MaxGrabAttempts = 3;

    // La finestra delle ricerche finite da cui si stima il ritmo della coda.
    private static readonly TimeSpan RateWindow = TimeSpan.FromHours(2);

    // Solo sotto _lock, solo in memoria. Le ricerche del giro finite da quando la coda non è più vuota, e quando
    // è finita ognuna (le ultime RateWindow, non si azzerano con la coda): l'avanzamento della panoramica.
    private int _autoSearched;
    private readonly List<DateTimeOffset> _searchFinishes = [];

    // Quante durate delle ricerche automatiche finite si tengono, e quante ne servono per una durata tipica.
    private const int TypicalWindow = 10;
    private const int TypicalMinimum = 3;

    // Solo sotto _lock, solo in memoria. Le durate in secondi delle ultime TypicalWindow ricerche automatiche.
    private readonly List<double> _autoDurations = [];

    // Solo sotto _lock. Il giro si è fermato per una ricerca dell'admin: alla fine dell'ultima si chiede un giro (Nudge).
    private bool _heldForManual;

    // Solo sotto _lock, solo in memoria. Un "Scarica subito" chiede al giro in corso di fermarsi dopo la ricerca che sta facendo.
    // Un evento una tantum, non una condizione letta dalle voci: si azzera solo all'inizio di RunCycleAsync.
    private bool _rushRequested;

    // Solo sotto _lock, solo in memoria. "Aggiorna ora" aspetta un giro che rilegga Sonarr e Radarr: finché non l'ha fatto la panoramica lo dice.
    private bool _refreshPending;

    [GeneratedRegex(@" · (?:S(?<s>[0-9]+)E(?<e>[0-9]+)|Stagione (?<s>[0-9]+))$")]
    private static partial Regex RushTitleRegex();

    // (stagione, episodio) dal fondo del titolo ("Serie · S03E05", "Serie · Stagione 3" = (3, 0)); gli altri titoli vanno in fondo.
    private static (int Season, int Episode) RushOrder(string title) =>
        RushTitleRegex().Match(title) is { Success: true } m
            ? (int.Parse(m.Groups["s"].Value, CultureInfo.InvariantCulture), m.Groups["e"].Success ? int.Parse(m.Groups["e"].Value, CultureInfo.InvariantCulture) : 0)
            : (int.MaxValue, 0);

    // Le voci con la ricerca scaduta, prima quelle con la precedenza (RushAt), poi dalla più vecchia; al massimo MaxSearchesPerCycle
    // ricerche (non per quelle con la precedenza), una alla volta.
    private async Task<(int Searched, int Grabbed)> SearchDueAsync(
        IReadOnlyDictionary<ArrKind, ArrView> views, Dictionary<ArrKind, string?> errors, CancellationToken cancellationToken)
    {
        List<string> due;
        HashSet<string> rushed;
        lock (_lock)
        {
            var now = time.GetUtcNow();

            // La voce non si cerca più (scarica, è passata ad altro): la precedenza non ha più senso.
            foreach (var entry in Book.Entries.Where(e => e.RushAt is not null && !CanRush(e)))
            {
                entry.RushAt = null;
            }

            due =
            [
                .. Book.Entries.Where(e => IsDue(e, views, now))
                    .OrderBy(e => e.RushAt ?? DateTimeOffset.MaxValue)
                    .ThenBy(e => e.RushAt is null ? e.NextSearchAt : null)

                    // Con la stessa precedenza (una serie intera): stagioni ed episodi in ordine, la serie riparte dall'inizio.
                    .ThenBy(e => e.RushAt is null ? 0 : RushOrder(e.Title).Season)
                    .ThenBy(e => e.RushAt is null ? 0 : RushOrder(e.Title).Episode)
                    .ThenBy(e => e.RushAt is null ? "" : e.Title, StringComparer.Ordinal)
                    .Select(e => e.Key),
            ];
            rushed = [.. Book.Entries.Where(e => e.RushAt is not null).Select(e => e.Key)];
        }

        var contexts = new Dictionary<ArrKind, SearchContext?>();
        var searched = 0;
        var grabbed = 0;
        foreach (var key in due)
        {
            if (searched >= MaxSearchesPerCycle && !rushed.Contains(key))
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

            // Una ricerca dell'admin aspetta o è in corso: niente ricerche nuove, riprende alla sua fine (ManualSearchAsync).
            // Nello stesso lock dell'aggiunta: una ricerca dell'admin che parte adesso aspetta questa.
            DateTimeOffset started;
            lock (_lock)
            {
                if (ManualSearching())
                {
                    _heldForManual = true;
                    break;
                }

                // Un "Scarica subito" (o una stagione con la precedenza che si è divisa) è arrivato: il giro nuovo riparte da quelle righe.
                if (_rushRequested)
                {
                    break;
                }

                started = time.GetUtcNow();
                _searching[item.Key] = started;
            }

            searched++;

            try
            {
                if (await SearchOneAsync(item, context, cancellationToken).ConfigureAwait(false))
                {
                    grabbed++;
                }
            }
            finally
            {
                lock (_lock)
                {
                    _searching.Remove(item.Key);

                    // Qualunque esito: la voce riprende il ritmo normale. Allo spegnimento no: il riavvio non perde RushAt.
                    if (!cancellationToken.IsCancellationRequested && Book.Get(item.Key) is { } done)
                    {
                        done.RushAt = null;
                    }

                    var now = time.GetUtcNow();
                    _autoSearched++;
                    _searchFinishes.Add(now);
                    _searchFinishes.RemoveAll(t => t < now - RateWindow);
                    _autoDurations.Add((now - started).TotalSeconds);
                    if (_autoDurations.Count > TypicalWindow)
                    {
                        _autoDurations.RemoveAt(0);
                    }

                    // Le ricerche dell'admin che aspettavano questa partono.
                    if (_searching.Count == 0)
                    {
                        _autoIdle?.TrySetResult();
                        _autoIdle = null;
                    }
                }
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
        var indexers = ByKey((await arr.GetIndexersAsync(kind, cancellationToken).ConfigureAwait(false)).OfType<ArrIndexer>(), i => i.Id);
        ChecksContext? checks = null;
        if (_finder.UsesProwlarr)
        {
            var definitions = await arr.GetQualityDefinitionsAsync(kind, cancellationToken).ConfigureAwait(false);
            var releaseProfiles = await arr.GetReleaseProfilesAsync(kind, cancellationToken).ConfigureAwait(false);
            var blocklist = await arr.GetBlocklistAsync(kind, cancellationToken).ConfigureAwait(false);
            checks = new ChecksContext(
                null,
                [.. definitions.OfType<ArrQualityDefinition>()],
                [.. releaseProfiles.OfType<ArrReleaseProfile>()],
                [.. blocklist.OfType<ArrBlocklistItem>()],
                indexers.Where(i => i.Value.MinimumSeeders is not null).ToDictionary(i => i.Key, i => i.Value.MinimumSeeders!.Value),
                []);
        }

        return new SearchContext(
            ByKey(profiles.OfType<ArrQualityProfile>(), p => p.Id),
            indexers.ToDictionary(p => p.Key, p => p.Value.Priority),
            checks);
    };

    // I controlli per il titolo cercato: il suo profilo, i suoi tag e solo le sue voci di blocklist.
    // TitleId: il film (Radarr) o la serie (Sonarr).
    private static ChecksContext ChecksFor(ChecksContext checks, ArrKind service, int titleId, IReadOnlyList<int> tags, ArrQualityProfile? profile) => checks with
    {
        Profile = profile,
        TitleTags = tags,
        Blocklist = [.. checks.Blocklist.Where(b => (service == ArrKind.Radarr ? b.MovieId : b.SeriesId) == titleId)],
    };

    // Solo sotto _lock. Waiting e NeedsYou (non ImportBlocked) di un titolo ancora da scaricare, o UpgradeWatch;
    // solo per i servizi letti in questo giro: degli altri non si sa se il titolo è in coda. Se l'admin lo sta già cercando non si fa un doppione.
    private bool IsDue(DownloadEntry entry, IReadOnlyDictionary<ArrKind, ArrView> views, DateTimeOffset now) =>
        entry.NextSearchAt <= now
        && !AdminSearching(entry.Key)
        && views.TryGetValue(ServiceOf(entry.Kind), out var view)
        && SearchesByState(entry)
        && (entry.State == DownloadStates.UpgradeWatch || view.Titles.GetValueOrDefault(entry.Key)?.Wanted == true);

    // Solo sotto _lock. Le voci da cercare adesso dal giro (anche spento), con quelle che sta cercando; non quelle dell'admin.
    private int Backlog(DateTimeOffset now) =>
        Book.Entries.Count(e => _searching.ContainsKey(e.Key) || (e.NextSearchAt <= now && SearchesByState(e) && !AdminSearching(e.Key)));

    // Solo sotto _lock. Null con la coda vuota. Il ritmo con almeno 3 ricerche nella finestra (su almeno 15 minuti), la fine solo se il giro è acceso
    // e nessuna ricerca dell'admin lo tiene fermo.
    private SearchProgressDto? SearchProgress(DateTimeOffset now)
    {
        var remaining = Backlog(now);
        if (remaining == 0)
        {
            return null;
        }

        var recent = _searchFinishes.Where(t => t >= now - RateWindow).ToList();
        double? perHour = recent.Count < 3 ? null : recent.Count / Math.Max((now - recent[0]).TotalHours, 0.25);
        var paused = !settings.Enabled;
        var manual = ManualSearching();
        DateTimeOffset? end = paused || manual || perHour is null ? null : now + TimeSpan.FromHours(remaining / perHour.Value);
        return new SearchProgressDto(_autoSearched, remaining, perHour, end, paused, manual);
    }

    // Solo sotto _lock. La parte di IsDue che dipende dallo stato (senza le viste di Radarr/Sonarr): lo usa anche la fase "Queued" della panoramica.
    private bool SearchesByState(DownloadEntry entry) => entry.State switch
    {
        DownloadStates.UpgradeWatch => !Book.IsAccepted(entry.Key),
        DownloadStates.Waiting => true,
        DownloadStates.NeedsYou => entry.Reason != DownloadReasons.ImportBlocked,
        _ => false,
    };

    private static SearchItem? ToSearchItem(DownloadEntry entry, ArrView view)
    {
        if (!DownloadKey.TryParse(entry.Key, out var key))
        {
            return null;
        }

        var upgrade = entry.State == DownloadStates.UpgradeWatch;
        var titleId = key.Kind == DownloadKinds.Episode ? entry.SeriesId : key.Id;
        var tags = view.Titles.GetValueOrDefault(entry.Key)?.Tags ?? [];
        var item = new SearchItem(
            entry.Key, ServiceOf(key.Kind), key, upgrade, entry.ProfileId, entry.RuntimeMinutes, entry.CurrentScore, entry.CurrentQualityId, (entry.RefusedReleases ?? []).ToHashSet(), entry.Stopgap, titleId, tags);
        if (key.Kind != DownloadKinds.Season)
        {
            return item;
        }

        // Gli episodi che mancano, o per un upgrade quelli del pack scaricato.
        var season = view.Seasons?.GetValueOrDefault(entry.Key);
        var episodes = upgrade ? entry.EpisodeNumbers : season?.Missing;
        return episodes is { Count: > 0 } ? item with { Episodes = episodes, SplitInto = season?.Episodes, SeasonNoFiles = season?.NoFiles == true } : null;
    }

    // Una ricerca e quello che ne segue; true se ha scaricato.
    private async Task<bool> SearchOneAsync(SearchItem item, SearchContext context, CancellationToken cancellationToken)
    {
        var profile = context.Profiles.GetValueOrDefault(item.ProfileId);
        FinderResult found;
        try
        {
            found = await _finder.SearchAsync(item.Target, SearchEngine.Prowlarr, cancellationToken, ArrClient.CycleSearchTimeout).ConfigureAwait(false);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Download automatici: ricerca di {Key} su {Kind} non riuscita ({Error})", item.Key, item.Service, ErrorOf(ex));

            // Una stagione troppo lunga per la ricerca di Sonarr non finirebbe mai: un episodio alla volta ci sta. Un upgrade resta com'è.
            // Con Prowlarr ogni query è breve: un timeout non dice niente della stagione.
            if (ex is ArrException { TimedOut: true } && !_finder.UsesProwlarr && item.Episodes is not null && !item.Upgrade)
            {
                Split(item);
                return false;
            }

            Update(item.Key, (entry, now) =>
            {
                // Si riprova al giro dopo, ma dietro alle voci che aspettano già. Dopo un timeout molto più tardi.
                entry.LastSearchAt = now;
                entry.Reason = DownloadReasons.SearchFailed;
                entry.NextSearchAt = now + (ex is not ArrException { TimedOut: true } ? CycleInterval : item.Upgrade ? DownloadSchedule.TimedOutUpgradePace : DownloadSchedule.TimedOutPace);
            });
            return false;
        }

        var releases = found.Releases;

        // Le release che il client di download ha già rifiutato non si scelgono più, per nessuna regola.
        if (item.Refused.Count > 0)
        {
            releases = [.. releases.Where(r => r is null || r.Guid is null || !item.Refused.Contains(DownloadRule.ReleaseId(r.Guid, r.IndexerId)))];
        }

        var thresholds = settings.For(item.Service, item.ProfileId, profile?.Name);
        var input = new RuleInput(
            item.RuntimeMinutes,
            item.Service == ArrKind.Radarr,
            settings.MinGbPerHour,
            thresholds.MinScore,
            context.IndexerPriority,
            context.Checks is { } checks ? ChecksFor(checks, item.Service, item.TitleId, item.Tags, profile) : null);

        // Un tappabuchi ignora solo il punteggio minimo di WonderFlix: peso e rifiuti di Radarr/Sonarr valgono (spec §5.1).
        var stopgap = item.Upgrade ? item.Stopgap : null;
        if (stopgap is not null)
        {
            input = input with { MinScore = int.MinValue };
        }

        // I candidati in ordine di regola, il primo è la scelta; vuoto se non c'è una scelta.
        IReadOnlyList<ArrRelease> ranked;
        RuleResult? rule = null;
        if (item.Episodes is { } episodes)
        {
            // Una stagione: il pack se conviene (spec T §5.4), poi gli altri pack validi; altrimenti si divide, un upgrade resta com'è.
            if (SeasonPackRule.PackCandidates(releases, episodes, input) is { Count: > 0 } packs)
            {
                // Anche i pack dopo il primo devono pesare poco più dei singoli.
                ranked = packs;
            }
            else if (!item.Upgrade)
            {
                // Solo pack 720p: la stagione non si divide e resta in "Serve te", con il tappabuchi per l'admin.
                // Solo se nessun episodio ha un file: il pack li importerebbe tutti, e Sonarr cancella i file sostituiti.
                if (item.SeasonNoFiles && SeasonPackRule.QualityPack(releases, episodes, input) is { } qualityPack)
                {
                    rule = qualityPack;
                    NothingValid();
                    return false;
                }

                FoundLittle();
                Split(item);
                return false;
            }
            else
            {
                ranked = [];
            }
        }
        else
        {
            rule = DownloadRule.Choose(releases, input);
            ranked = rule.Choice is null ? [] : rule.Candidates;
        }

        // La scelta, se si scarica, poi le successive che si scaricherebbero: si provano solo dopo un rifiuto di regola del push.
        var attempts = new List<(ArrRelease Release, bool ForceImport)>();
        if (ranked.Count > 0 && Acceptable(ranked[0]) is { } first)
        {
            attempts.Add((ranked[0], first));
            foreach (var next in ranked.Skip(1))
            {
                if (attempts.Count >= MaxGrabAttempts)
                {
                    break;
                }

                if (Acceptable(next) is { } forceImport)
                {
                    attempts.Add((next, forceImport));
                }
            }
        }

        if (attempts.Count == 0)
        {
            NothingValid();
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

        bool? grabbed;
        try
        {
            grabbed = await GrabChoicesAsync(item, attempts, profile, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            lock (_lock)
            {
                _grabbing.Remove(item.Key);
            }
        }

        if (grabbed is { } done)
        {
            return done;
        }

        // Tutte rifiutate per regola dal push: come se non ci fosse niente di valido (una stagione si divide).
        if (item.Episodes is not null && !item.Upgrade)
        {
            Split(item);
        }
        else
        {
            NothingValid();
        }

        return false;

        // Si scarica? Il valore è ForceImport: un tappabuchi per peso che Radarr/Sonarr non importerebbero. Null se no.
        bool? Acceptable(ArrRelease choice)
        {
            if (choice.CustomFormatScore < input.MinScore)
            {
                return null;
            }

            if (stopgap is not null)
            {
                // Per punteggio: più alto e importato da Radarr/Sonarr. Per peso: anche pari, e se non lo importerebbero si importa a mano.
                var wouldImport = profile is not null
                    && DownloadRule.WouldImport(profile, choice.Quality?.Quality?.Id ?? 0, choice.CustomFormatScore, item.CurrentQualityId, item.CurrentScore);
                var current = item.CurrentScore ?? 0;
                // Per qualità (un 720p): anche pari, purché lo importino, così non si perde l'audio italiano con un punteggio più basso.
                var accepted = stopgap == DownloadStopgaps.Size ? choice.CustomFormatScore >= current
                    : stopgap == DownloadStopgaps.Quality ? choice.CustomFormatScore >= current && wouldImport
                    : choice.CustomFormatScore > current && wouldImport;
                return accepted ? !wouldImport : null;
            }

            return item.Upgrade && !IsUpgrade(choice, item, profile) ? null : false;
        }

        void NothingValid()
        {
            if (!item.Upgrade)
            {
                FoundLittle();
            }

            // Il riassunto (anche di una stagione, col suo pack 720p), ma non per un upgrade che non conviene.
            var count = releases.Count(r => !string.IsNullOrEmpty(r?.Guid));
            Update(item.Key, (entry, now) => NothingChosen(entry, item.Upgrade ? null : rule, thresholds.MinScore, count, now));
        }

        // "Trovato poco" nel giro è solo una riga di log (spec ricerche-prowlarr §7).
        void FoundLittle()
        {
            if (found.Engine == SearchEngine.Prowlarr)
            {
                logger.LogInformation("Download automatici: {Key}, Prowlarr ha trovato poco ({Found} release, {WrongTitle} di altri titoli)", item.Key, releases.Count, found.WrongTitle.Count);
            }
        }
    }

    // Solo sotto _lock. Si ricorda la release rifiutata dal client (al massimo 20, via le più vecchie): la ricerca dopo ne sceglie un'altra.
    private static void RememberRefused(DownloadEntry entry, string guid, int indexerId) =>
        entry.RefusedReleases = [.. (entry.RefusedReleases ?? []).Append(DownloadRule.ReleaseId(guid, indexerId)).TakeLast(MaxRefusedReleases)];

    // Il grab delle scelte del giro, una dopo l'altra finché il push le rifiuta per regola. True se ha scaricato, false se il
    // client l'ha rifiutata o il grab non è riuscito, null se il push le ha rifiutate tutte per regola.
    private async Task<bool?> GrabChoicesAsync(
        SearchItem item, IReadOnlyList<(ArrRelease Release, bool ForceImport)> attempts, ArrQualityProfile? profile, CancellationToken cancellationToken)
    {
        string? firstReason = null;
        foreach (var (choice, forceImport) in attempts)
        {
            GrabResult result;
            try
            {
                result = await _finder.GrabAsync(item.Service, choice, forceImport, cancellationToken).ConfigureAwait(false);
            }
            catch (ArrException ex) when (ex.Status >= 500 && !cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning("Download automatici: {Key}, {Kind} ha avuto la scelta rifiutata dal client ({Error}, stato {Status})", item.Key, item.Service, ErrorOf(ex), ex.Status);
                ClientRefused(choice);
                return false;
            }
            catch (QbitException ex) when (ex.Error == QbitError.Refused && !cancellationToken.IsCancellationRequested)
            {
                // qBittorrent ha risposto "Fails." (di solito il torrent c'è già): come un rifiuto del client.
                logger.LogWarning("Download automatici: {Key}, qBittorrent ha rifiutato la scelta", item.Key);
                ClientRefused(choice);
                return false;
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                // Anche un qBittorrent giù o lento (QbitException).
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

            if (result.Kind == GrabKind.RuleRefused)
            {
                // Un rifiuto di regola non è del client: niente "Serve te" né RefusedReleases, si prova la prossima.
                firstReason ??= result.Reason;
                continue;
            }

            if (result.Kind == GrabKind.ClientRefused)
            {
                logger.LogWarning("Download automatici: {Key}, {Kind} ha avuto la scelta rifiutata dal client", item.Key, item.Service);
                ClientRefused(choice);
                return false;
            }

            logger.LogInformation("Download automatici: {Key} scaricato da {Kind}", item.Key, item.Service);
            lock (_lock)
            {
                if (Book.Get(item.Key) is { } entry)
                {
                    Grabbed(entry, choice, item.Upgrade, profile?.Name, time.GetUtcNow());
                    entry.EpisodeNumbers = item.Episodes?.ToList();
                    entry.ManualImportPending = forceImport;

                    // Un torrent messo da noi in qBittorrent: lo segue ApplyDirect, non la coda.
                    if (result.Kind == GrabKind.Direct && result.Hash is { } hash)
                    {
                        entry.DirectHash = hash;
                        Book.DirectGrabs[hash] = item.Key;
                    }
                }

                // Subito su disco: un riavvio prima della fine del giro non deve perdere il download.
                store.Save(Book);
            }

            return true;
        }

        // Il motivo è di Sonarr/Radarr, mai il titolo.
        logger.LogInformation("Download automatici: {Key}, {Kind} ha rifiutato per regola {Count} release ({Reason})", item.Key, item.Service, attempts.Count, firstReason);
        return null;

        void ClientRefused(ArrRelease choice) => Update(item.Key, (entry, now) =>
        {
            // Il client di download ha rifiutato la release (per esempio il torrent c'è già): riprovare ogni giro è inutile, si avvisa l'admin e si riprova piano.
            entry.LastSearchAt = now;
            entry.Reason = DownloadReasons.GrabRefused;
            entry.NextSearchAt = now + CycleInterval;

            RememberRefused(entry, choice.Guid!, choice.IndexerId);
            if (entry.State != DownloadStates.UpgradeWatch)
            {
                entry.State = DownloadStates.NeedsYou;
            }
        });
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
    private static void NothingChosen(DownloadEntry entry, RuleResult? rule, int minScore, int found, DateTimeOffset now)
    {
        var belowMinScore = rule?.BelowMinScore == true;
        entry.LastSearchAt = now;
        entry.NextSearchAt = DownloadSchedule.Next(SinceOf(entry), now);
        if (entry.State == DownloadStates.UpgradeWatch)
        {
            // Il file c'è già: niente "Serve te".
            entry.Reason = null;
            return;
        }

        if (rule is not null)
        {
            entry.Summary = DownloadRule.Summarize(rule, found, minScore);
        }

        if (entry.Snoozed && !belowMinScore)
        {
            // Silenziato dall'admin: parla di nuovo solo se compare qualcosa sotto il minimo.
            (entry.State, entry.Reason, entry.NextSearchAt) = (DownloadStates.Waiting, DownloadReasons.NothingFound, now + DownloadSchedule.SnoozedPace);
            return;
        }

        if (belowMinScore)
        {
            entry.Snoozed = false;
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
        entry.Snoozed = false;
        entry.Summary = null;
        entry.LastSearchAt = now;
        entry.MetadataSince = null;
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
            // Solo per un tappabuchi per peso: più pesante del download di prima con la stessa qualità e lo stesso punteggio è il suo import forzato.
            // Negli altri upgrade PreviousSizeBytes è spesso il peso della release, non del file: il peso non conta.
            if (files.Count > 0
                && files.All(f => f.CustomFormatScore == previousScore && f.Quality?.Quality?.Id == entry.PreviousQualityId)
                && (entry.Stopgap != DownloadStopgaps.Size || files.Sum(f => f.Size) <= (entry.PreviousSizeBytes ?? long.MaxValue)))
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
        entry.MetadataSince = null;
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
