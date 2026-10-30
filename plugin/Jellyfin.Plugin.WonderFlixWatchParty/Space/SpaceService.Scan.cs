using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Il calcolo dello spazio e la panoramica per chi chiama (spec U §5 e §7.3).</summary>
public sealed partial class SpaceService
{
    /// <summary>Richieste di Seerr per pagina (decisione 9).</summary>
    private const int SeerrPageSize = 100;

    /// <summary>L'utente Seerr con cui si leggono le richieste: l'admin (decisione 9).</summary>
    private const int SeerrAdmin = 1;

    /// <summary>Quanti "generi che guardi spesso" (spec U §4.4).</summary>
    private const int TopGenreCount = 3;

    /// <summary>Le operazioni nella panoramica, dalla più recente.</summary>
    private const int OverviewOperations = 20;

    private const double SecondsPerDay = 86_400;

    /// <summary>Le cartelle degli extra di Jellyfin: i video lì dentro non sono doppioni del film (spec U §5.3).</summary>
    private static readonly HashSet<string> ExtrasFolders = new(
        ["extras", "featurettes", "behind the scenes", "deleted scenes", "interviews", "scenes", "shorts", "trailers", "other", "samples"],
        StringComparer.OrdinalIgnoreCase);

    // 1 mentre un calcolo è in corso.
    private int _scanning;

    // 1 dopo il primo tentativo di calcolo, riuscito o no.
    private int _attempted;

    /// <summary>
    /// Vero mentre un calcolo è in corso e dall'avvio fino al primo (spec U §7.3); dopo un primo tentativo fallito è falso
    /// con <c>ScannedAt</c> null.
    /// </summary>
    public bool Scanning => Volatile.Read(ref _scanning) != 0 || (LastScan is null && Volatile.Read(ref _attempted) == 0);

    /// <summary>
    /// Calcola e sostituisce <see cref="LastScan"/> (spec U §7.3). Uno alla volta: una seconda chiamata durante un calcolo
    /// ritorna subito. Se il calcolo non riesce (<c>stat</c> che non risponde, Jellyfin che lancia) resta quello di prima:
    /// file che non si sono potuti leggere non vanno trattati come mancanti.
    /// </summary>
    public async Task ScanAsync(CancellationToken ct)
    {
        if (Interlocked.Exchange(ref _scanning, 1) != 0)
        {
            return;
        }

        try
        {
            var scan = await BuildScanAsync(ct).ConfigureAwait(false);
            LastScan = scan;
            logger.LogInformation(
                "Spazio: calcolo finito, {Delete} da cancellare, {Lighten} da alleggerire, {Torrents} torrent, {Orphans} orfani, {Duplicates} doppioni",
                scan.Delete.Count,
                scan.Lighten.Count,
                scan.Cleanup.Torrents.Count,
                scan.Cleanup.Orphans.Count,
                scan.Cleanup.Duplicates.Count);
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            // Solo il tipo: il messaggio potrebbe contenere un percorso.
            logger.LogWarning("Spazio: calcolo non riuscito ({Error}), resta quello di prima", ex.GetType().Name);
        }
        finally
        {
            Volatile.Write(ref _attempted, 1);
            Volatile.Write(ref _scanning, 0);
        }
    }

    /// <summary>
    /// <c>GET Space</c> (spec U §7.4): l'ultimo calcolo senza i titoli tenuti e senza i preferiti di chi chiama (spec U §4.2),
    /// con i suoi generi (decisione 14), i torrent in attesa, i tenuti e le ultime operazioni.
    /// </summary>
    public SpaceOverviewDto Overview(Guid callerId)
    {
        var scan = LastScan;
        HashSet<string> keptKeys;
        List<SpaceKeptDto> kept;
        List<SpacePendingDto> pending;
        List<SpaceOperationDto> operations;
        List<SpaceOperation> done;
        lock (_lock)
        {
            // Le operazioni finite dopo il calcolo: le loro righe non valgono più fino al calcolo dopo.
            done = [.. Book.Operations.Where(o => o.State == SpaceOperationStates.Done && !o.Auto && o.StartedAt > (scan?.ScannedAt ?? DateTimeOffset.MinValue))];
            keptKeys = [.. Book.Kept.Select(k => k.Key)];
            kept = [.. Book.Kept.Select(k => new SpaceKeptDto(k.Key, k.Title))];
            pending = [.. Book.Pending.Select(p => new SpacePendingDto(p.Hash, p.Name, p.Tracker, p.SizeBytes, p.ExpectedAt, p.Title))];
            operations = [.. Book.Operations.Take(OverviewOperations).Select(o => o.ToDto())];
        }

        var doneKeys = done.Select(o => o.Key).ToHashSet();
        var removedHashes = done.SelectMany(o => o.RemovedHashes).ToHashSet();
        bool Visible(IReadOnlyList<string> keys, IReadOnlyList<Guid> itemIds) =>
            !keys.Any(keptKeys.Contains) && !itemIds.Any(id => viewing.IsFavorite(callerId, id));

        // Una riga fatta: la sua chiave, o la serie (per le stagioni); le altre chiavi di Keys servono solo ai tenuti.
        bool Done(string key, string? seriesKey) => doneKeys.Contains(key) || (seriesKey is not null && doneKeys.Contains(seriesKey));

        IReadOnlyCollection<Guid> caller = [callerId];
        var highlyRated = (scan?.RatedItems ?? [])
            .Where(id => ratings.Of(id, caller).TryGetValue(callerId, out var rating) && rating.Score >= settings.HighRating)
            .ToHashSet();
        var shown = scan ?? new SpaceScan();
        return new SpaceOverviewDto(
            shown.ScannedAt,
            Scanning,
            shown.Quota,
            shown.Breakdown,
            [.. shown.Delete.Where(r => Visible(r.Keys, r.ItemIds) && !Done(r.Dto.Key, r.Dto.SeriesKey)).Select(r => r.Dto)],
            [.. shown.Lighten.Where(r => Visible(r.Keys, r.ItemIds) && !r.Keys.Any(doneKeys.Contains)).Select(r => r.Dto)],
            new SpaceCleanupDto(
                [.. shown.Cleanup.Torrents.Where(t => !removedHashes.Contains(t.Hash))],
                [.. shown.Cleanup.Orphans.Where(f => !doneKeys.Contains(f.Key))],
                [.. shown.Cleanup.Duplicates.Where(f => !doneKeys.Contains(f.Key))]),
            pending,
            kept,
            operations,
            viewing.TopGenres(callerId, highlyRated, TopGenreCount),
            shown.Errors);
    }

    /// <summary>La chiave di un file orfano o doppione: i primi 16 caratteri esadecimali dello SHA-256 del percorso (decisione 11).</summary>
    internal static string FileKey(string path) =>
        "file:" + Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(path)))[..16];

    private async Task<SpaceScan> BuildScanAsync(CancellationToken ct)
    {
        var (movies, radarrError) = await ReadMoviesAsync(ct).ConfigureAwait(false);
        var (series, sonarrError) = await ReadSeriesAsync(ct).ConfigureAwait(false);
        var (live, qbitError) = await ReadScanTorrentsAsync(ct).ConfigureAwait(false);
        var (requests, seerrError) = await ReadRequestsAsync(ct).ConfigureAwait(false);
        var (queued, radarrQueueError, sonarrQueueError) = live is null ? (null, null, null) : await QueuedHashesAsync(ct).ConfigureAwait(false);
        if (live is not null && queued is null)
        {
            radarrError ??= radarrQueueError is null ? null : Unanswered("Radarr", radarrQueueError);
            sonarrError ??= sonarrQueueError is null ? null : Unanswered("Sonarr", sonarrQueueError);
        }

        // Senza i torrent non si sa quali file sono loro: niente orfani, si mostrerebbero file in seed.
        IReadOnlyList<string> scanVideos = live is null ? [] : [.. settings.ScanFolders.SelectMany(folder => probe.VideoFiles(folder)).Distinct()];
        var duplicates = DuplicateCandidates(movies, series);
        var libraryPaths = movies.Select(m => m.MovieFile?.Path).Concat(series.SelectMany(s => s.Files.Select(f => f.Path))).OfType<string>().ToHashSet();
        var stamps = await probe.StatAsync(
            [.. libraryPaths.Concat(duplicates.Select(d => d.Path)).Concat(scanVideos).Distinct()], ct).ConfigureAwait(false);

        // I file che Radarr/Sonarr conoscono, per percorso e per id: mai orfani né doppioni.
        var known = new KnownFiles(libraryPaths, libraryPaths.Where(stamps.ContainsKey).Select(p => stamps[p].Id).ToHashSet());
        var index = live?.Index ?? new TorrentIndex([], new Dictionary<string, IReadOnlyList<TorrentFile>>());
        var libraryFiles = known.Ids.Union(live?.LibraryFiles ?? []).ToHashSet();
        var now = time.GetUtcNow();
        var titles = BuildTitles(new ScanData(movies, series, requests, stamps, index, libraryFiles), now);
        var files = new Dictionary<string, ScanFile>();
        var (cleanup, torrents) = BuildCleanup(live, queued, scanVideos, duplicates, stamps, known, files, now);
        var quota = ReadQuota();
        return new SpaceScan
        {
            ScannedAt = now,
            Quota = quota is null ? null : new SpaceQuotaDto(quota.UsedBytes, quota.LimitBytes),
            Breakdown = Breakdown(movies, series, cleanup, quota),
            Delete = titles.Delete,
            Lighten = titles.Lighten,
            Cleanup = cleanup,
            Errors = new SpaceErrorsDto(radarrError, sonarrError, qbitError, seerrError, quota is null ? SpaceDetails.NotConfigured : null),
            RatedItems = titles.RatedItems,
            Titles = titles.Titles,
            Files = files,
            Torrents = torrents,
        };
    }

    private async Task<(IReadOnlyList<RadarrMovie> Movies, string? Error)> ReadMoviesAsync(CancellationToken ct)
    {
        try
        {
            return ([.. (await arr.GetLibraryMoviesAsync(ct).ConfigureAwait(false)).OfType<RadarrMovie>()], null);
        }
        catch (ArrException ex)
        {
            return ([], Unanswered("Radarr", UpcomingErrors.Code(ex.Error)));
        }
    }

    /// <summary>Le serie di Sonarr con i file dei loro episodi; una serie tolta nel frattempo (404) si salta.</summary>
    private async Task<(IReadOnlyList<ScanSeries> Series, string? Error)> ReadSeriesAsync(CancellationToken ct)
    {
        try
        {
            var found = new List<ScanSeries>();
            foreach (var show in (await arr.GetSeriesAsync(ct).ConfigureAwait(false)).OfType<SonarrSeries>())
            {
                try
                {
                    found.Add(new ScanSeries(show, [.. (await arr.GetEpisodeFilesAsync(show.Id, ct).ConfigureAwait(false)).OfType<ArrFile>()]));
                }
                catch (ArrException ex) when (ex.Status == 404)
                {
                    // Tolta nel frattempo.
                }
            }

            return (found, null);
        }
        catch (ArrException ex)
        {
            return ([], Unanswered("Sonarr", UpcomingErrors.Code(ex.Error)));
        }
    }

    /// <summary>
    /// I torrent con i loro file, con l'aiuto delle operazioni (<see cref="ReadTorrentsAsync"/>): <c>torrents/files</c> per
    /// ognuno, perché <c>content_path</c> da solo non distingue un torrent di un file da una cartella.
    /// </summary>
    private async Task<(LiveTorrents? Live, string? Error)> ReadScanTorrentsAsync(CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(settings.QbitUrl))
        {
            return (null, SpaceDetails.NotConfigured);
        }

        try
        {
            return (await ReadTorrentsAsync(ct).ConfigureAwait(false), null);
        }
        catch (QbitException ex)
        {
            return (null, Unanswered("qBittorrent", CodeOf(ex.Error)));
        }
    }

    /// <summary>Tutte le richieste di Seerr, pagina per pagina, come l'admin (decisione 9).</summary>
    private async Task<(IReadOnlyList<SeerrRequest> Requests, string? Error)> ReadRequestsAsync(CancellationToken ct)
    {
        if (!seerrSettings.IsConfigured())
        {
            return ([], SpaceDetails.NotConfigured);
        }

        try
        {
            var all = new List<SeerrRequest>();
            var skip = 0;
            while (true)
            {
                var page = await seerr.GetRequestsAsync(SeerrAdmin, "all", SeerrPageSize, skip, null, ct).ConfigureAwait(false);
                var results = page.Results ?? [];
                skip += results.Count;
                all.AddRange(results.OfType<SeerrRequest>());
                if (results.Count == 0 || skip >= (page.PageInfo?.Results ?? 0))
                {
                    return (all, null);
                }
            }
        }
        catch (SeerrException ex)
        {
            return ([], Unanswered("Seerr", CodeOf(ex.Error)));
        }
    }

    // Il codice dell'errore, con un avviso nel registro se il servizio è configurato ma non risponde.
    private string Unanswered(string service, string code)
    {
        if (code != SpaceDetails.NotConfigured)
        {
            logger.LogWarning("Spazio: {Service} non risponde ({Error}), le sue liste restano vuote", service, code);
        }

        return code;
    }

    /// <summary>
    /// I video nelle cartelle dei titoli che Radarr/Sonarr non conoscono (spec U §5.3), con il titolo che li contiene.
    /// Solo per i titoli con almeno un file: altrimenti il video in più sarebbe l'unica copia.
    /// </summary>
    private List<(string Path, string Owner)> DuplicateCandidates(IReadOnlyList<RadarrMovie> movies, IReadOnlyList<ScanSeries> series)
    {
        var movieFiles = movies
            .Where(m => m.MovieFile?.Path is not null && !string.IsNullOrWhiteSpace(m.Path))
            .SelectMany(m => probe.VideoFiles(m.Path!)
                .Where(p => p != m.MovieFile!.Path && !InExtras(p, m.Path!))
                .Select(p => (p, MovieKey(m.Id))));

        // Di una serie è doppione solo un video con lo stesso SxxEyy di un episodio che Sonarr conosce.
        var episodeFiles = series
            .Where(s => s.Files.Count > 0 && !string.IsNullOrWhiteSpace(s.Show.Path))
            .SelectMany(s =>
            {
                var known = s.Files.Select(f => f.Path).OfType<string>().ToHashSet();
                var codes = known.Select(EpisodeCode).OfType<(int, int)>().ToHashSet();
                return probe.VideoFiles(s.Show.Path!)
                    .Where(p => !known.Contains(p) && EpisodeCode(p) is { } code && codes.Contains(code))
                    .Select(p => (p, SeriesKey(s.Show.Id)));
            });
        return [.. movieFiles.Concat(episodeFiles).DistinctBy(d => d.p)];
    }

    /// <summary>Vero se tra la cartella del film e il file c'è una cartella di extra di Jellyfin.</summary>
    private static bool InExtras(string path, string folder) =>
        path[folder.TrimEnd('/').Length..].Split('/', StringSplitOptions.RemoveEmptyEntries).SkipLast(1).Any(ExtrasFolders.Contains);

    /// <summary>Stagione ed episodio (<c>SxxEyy</c>) dal nome del file; null se non c'è.</summary>
    private static (int Season, int Episode)? EpisodeCode(string path) =>
        EpisodeCodeRegex().Match(Path.GetFileName(path)) is { Success: true } m
            ? (int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture), int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture))
            : null;

    [GeneratedRegex(@"S(\d{1,2})E(\d{1,3})", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex EpisodeCodeRegex();

    /// <summary>
    /// La Pulizia (spec U §5.3): i torrent finiti senza copia in libreria e fuori dalle code di Radarr/Sonarr (nessuno se
    /// <paramref name="queued"/> è null), i video delle cartelle di Pulizia che non sono di nessun torrent e non hanno
    /// altri hardlink, e i doppioni. Riempie <paramref name="files"/> per le operazioni.
    /// </summary>
    private (SpaceCleanupDto Cleanup, Dictionary<string, TorrentFacts> Torrents) BuildCleanup(
        LiveTorrents? live,
        HashSet<string>? queued,
        IReadOnlyList<string> scanVideos,
        IReadOnlyList<(string Path, string Owner)> duplicates,
        IReadOnlyDictionary<string, FileStamp> stamps,
        KnownFiles known,
        Dictionary<string, ScanFile> files,
        DateTimeOffset now)
    {
        var torrents = new Dictionary<string, TorrentFacts>();
        var torrentRows = new List<SpaceTorrentDto>();
        var orphans = new List<SpaceFileDto>();
        if (live is not null)
        {
            var links = live.ById.ToDictionary(p => p.Key, p => p.Value.Links);
            foreach (var torrent in live.Index.Torrents.Where(t => t.Progress >= 1
                && queued is not null
                && !queued.Contains(t.Hash)
                && live.Index.FilesByHash.GetValueOrDefault(t.Hash) is { Count: > 0 }
                && SpaceMath.IsTorrentOnly(t.Hash, live.Index, links)))
            {
                var verdict = SeedRule.Check(torrent, settings.Seed, now);
                torrents[torrent.Hash] = torrent;
                torrentRows.Add(new SpaceTorrentDto(
                    TorrentPrefix + torrent.Hash,
                    torrent.Hash,
                    torrent.Name,
                    torrent.TrackerHost,
                    torrent.SizeBytes,
                    torrent.Ratio,
                    Math.Round(torrent.SeedingSeconds / SecondsPerDay, 1),
                    verdict.CanRemoveNow,
                    verdict.ExpectedAt));
            }

            // Né di un torrent (anche con un altro percorso per lo stesso file), né di un download in corso, né della libreria.
            var torrentPaths = live.Index.FilesByHash.Values.SelectMany(f => f).Select(f => f.Path).ToHashSet();

            // Un torrent finito di cui stat non vede nessun file: save_path non è quello che vede Jellyfin, e il legame
            // torrent -> file non è affidabile. Si mostrerebbero come orfani file in seed: niente orfani.
            var unseen = live.Index.Torrents.Count(t => t.Progress >= 1
                && live.PathsByHash.GetValueOrDefault(t.Hash) is { Count: > 0 }
                && live.Index.FilesByHash.GetValueOrDefault(t.Hash) is not { Count: > 0 });
            if (unseen > 0)
            {
                logger.LogWarning("Spazio: {Unseen} torrent finiti su {Total} senza file visibili, niente orfani in questo calcolo", unseen, live.Index.Torrents.Count);
            }

            orphans = unseen > 0 ? [] : [.. scanVideos
                .Where(p => !torrentPaths.Contains(p)
                    && stamps.TryGetValue(p, out var stamp)
                    && stamp.Links == 1
                    && !live.ById.ContainsKey(stamp.Id)
                    && !known.Contains(p, stamp)
                    && !FileProbe.IsUnder(p, live.IncompleteRoots))
                .Select(p => FileRow(p, SpaceKinds.Orphan, null, stamps, files))
                .OfType<SpaceFileDto>()];
        }

        // Un file che un titolo qualsiasi conosce non è mai il doppione di un altro.
        List<SpaceFileDto> duplicateRows = [.. duplicates
            .Where(d => stamps.TryGetValue(d.Path, out var stamp) && !known.Contains(d.Path, stamp))
            .Select(d => FileRow(d.Path, SpaceKinds.Duplicate, d.Owner, stamps, files))
            .OfType<SpaceFileDto>()];
        var cleanup = new SpaceCleanupDto(
            [.. torrentRows.OrderByDescending(t => t.CanRemoveNow).ThenByDescending(t => t.SizeBytes)],
            [.. orphans.OrderByDescending(f => f.SizeBytes)],
            [.. duplicateRows.OrderByDescending(f => f.SizeBytes)]);
        return (cleanup, torrents);
    }

    // La riga di un file, registrata anche per le operazioni; null se la chiave c'è già.
    private static SpaceFileDto? FileRow(
        string path, string kind, string? owner, IReadOnlyDictionary<string, FileStamp> stamps, Dictionary<string, ScanFile> files)
    {
        var key = FileKey(path);
        var stamp = stamps[path];
        return files.TryAdd(key, new ScanFile(path, kind, stamp.SizeBytes, owner))
            ? new SpaceFileDto(key, path, stamp.SizeBytes, stamp.Links > 1)
            : null;
    }

    /// <summary>Una serie di Sonarr con i file dei suoi episodi (spec U §5.1 e decisione 4).</summary>
    private sealed record ScanSeries(SonarrSeries Show, IReadOnlyList<ArrFile> Files);

    /// <summary>I file che Radarr/Sonarr conoscono, per percorso e per id: non sono "fuori da Radarr/Sonarr" (spec U §5.3).</summary>
    private sealed record KnownFiles(HashSet<string> Paths, HashSet<FileId> Ids)
    {
        public bool Contains(string path, FileStamp stamp) => Paths.Contains(path) || Ids.Contains(stamp.Id);
    }

    /// <summary>Quello che il calcolo ha letto, per costruire le liste dei titoli (spec U §7.3).</summary>
    private sealed record ScanData(
        IReadOnlyList<RadarrMovie> Movies,
        IReadOnlyList<ScanSeries> Series,
        IReadOnlyList<SeerrRequest> Requests,
        IReadOnlyDictionary<string, FileStamp> Stamps,
        TorrentIndex Index,
        HashSet<FileId> LibraryFiles);
}
