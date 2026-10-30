using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>I passi delle operazioni dello spazio, uno per uno (spec U §6.2).</summary>
public sealed partial class SpaceService
{
    /// <summary>
    /// Rilegge dal vivo i file del titolo, li passa a <c>stat</c>, legge i torrent e i loro file e calcola la stima
    /// (spec U §6.2). Senza qBittorrent configurato il passo è saltato e i torrent restano.
    /// </summary>
    private async Task<StepResult> FindTorrentsAsync(Run run, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(settings.QbitUrl))
        {
            return StepResult.Skipped(SpaceDetails.NotConfigured);
        }

        var stamps = await probe.StatAsync(await TitlePathsAsync(run, ct).ConfigureAwait(false), ct).ConfigureAwait(false);
        var live = await ReadTorrentsAsync(ct).ConfigureAwait(false);
        var fallback = stamps.Count == 0;
        IReadOnlyList<FileFact> files = fallback
            ? FallbackFiles(run.Scanned, live)
            : [.. stamps.Select(p => new FileFact(p.Key, p.Value.Id, p.Value.Links, p.Value.SizeBytes))];
        var estimate = SpaceMath.Estimate(files, live.Index, live.LibraryFiles, settings.Seed, time.GetUtcNow());
        if (fallback)
        {
            // Senza i file dal vivo vanno via solo i torrent che il calcolo aveva legato al titolo.
            var linked = run.Scanned?.Hashes.ToHashSet() ?? [];
            estimate = estimate with
            {
                RemoveNow = [.. estimate.RemoveNow.Where(linked.Contains)],
                RemoveLater = [.. estimate.RemoveLater.Where(linked.Contains)],
            };
        }

        run.Estimate = estimate;
        run.Facts = live.Index.Torrents.ToDictionary(t => t.Hash);
        (run.Freed, run.Pending) = (estimate.FreeNowBytes, estimate.FreeLaterBytes);
        return StepResult.Ok(estimate.RemoveNow.Count, estimate.RemoveLater.Count);
    }

    /// <summary>
    /// Nuovo tentativo dopo che Radarr/Sonarr hanno tolto i file: valgono gli id del calcolo, ma solo se un torrent che il
    /// calcolo aveva legato al titolo ha ancora quel file, con la stessa dimensione. Un inode liberato può tornare in un
    /// download nuovo che non c'entra.
    /// </summary>
    private static IReadOnlyList<FileFact> FallbackFiles(ScanTitle? title, LiveTorrents live)
    {
        if (title is null)
        {
            return [];
        }

        var held = title.Hashes
            .SelectMany(hash => live.Index.FilesByHash.GetValueOrDefault(hash) ?? [])
            .Select(f => f.Id)
            .ToHashSet();
        return [.. title.Files.Where(f => held.Contains(f.Id) && live.ById.TryGetValue(f.Id, out var now) && now.SizeBytes == f.SizeBytes)];
    }

    // I percorsi dei file del titolo da Radarr (moviefile) o Sonarr (episodefile); nessuno se il titolo non c'è più.
    private async Task<IReadOnlyList<string>> TitlePathsAsync(Run run, CancellationToken ct)
    {
        try
        {
            if (run.Kind == SpaceKinds.Movie)
            {
                var movie = await arr.GetMovieAsync(run.ArrId, ct).ConfigureAwait(false);
                return movie.MovieFile?.Path is { } path ? [path] : [];
            }

            var episodeFiles = await arr.GetEpisodeFilesAsync(run.ArrId, ct).ConfigureAwait(false);
            return [.. episodeFiles
                .Where(f => f is not null && (run.Kind == SpaceKinds.Series || f.SeasonNumber == run.Season))
                .Select(f => f!.Path)
                .OfType<string>()];
        }
        catch (ArrException ex) when (ex.Status == 404)
        {
            return [];
        }
    }

    /// <summary>
    /// I torrent di qBittorrent con i loro file su disco: l'indice, i file che hanno un hardlink fuori dai torrent
    /// (quelli in libreria) e lo <c>stat</c> di ogni file per id. I file che non sono su disco restano fuori.
    /// </summary>
    private async Task<LiveTorrents> ReadTorrentsAsync(CancellationToken ct)
    {
        var facts = new List<TorrentFacts>();
        var paths = new Dictionary<string, List<string>>();
        var incomplete = new List<string>();
        foreach (var torrent in await qbit.GetTorrentsAsync(ct).ConfigureAwait(false))
        {
            if (torrent.Progress < 1 && !string.IsNullOrEmpty(torrent.ContentPath))
            {
                incomplete.Add(torrent.ContentPath);
            }

            if (string.IsNullOrEmpty(torrent.Hash) || paths.ContainsKey(torrent.Hash))
            {
                continue;
            }

            try
            {
                var files = await qbit.GetFilesAsync(torrent.Hash, ct).ConfigureAwait(false);
                facts.Add(await FactsAsync(torrent, ct).ConfigureAwait(false));
                paths[torrent.Hash] = [.. files.Where(f => !string.IsNullOrEmpty(f.Name)).Select(f => PathOf(torrent, f.Name!))];
            }
            catch (QbitException ex) when (ex.Error == QbitError.NotFound)
            {
                // Tolto nel frattempo.
            }
        }

        var stamps = await probe.StatAsync([.. paths.Values.SelectMany(p => p).Distinct()], ct).ConfigureAwait(false);
        var filesByHash = paths.ToDictionary(
            p => p.Key,
            p => (IReadOnlyList<TorrentFile>)[.. p.Value.Where(stamps.ContainsKey).Select(path => new TorrentFile(path, stamps[path].Id))]);
        var libraryFiles = filesByHash.Values
            .SelectMany(files => files)
            .GroupBy(f => f.Id)
            .Where(g => stamps[g.First().Path].Links > g.Select(f => f.Path).Distinct().Count())
            .Select(g => g.Key)
            .ToHashSet();
        var byId = stamps.Values.DistinctBy(s => s.Id).ToDictionary(s => s.Id);
        var pathsByHash = paths.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value);
        return new LiveTorrents(new TorrentIndex(facts, filesByHash), libraryFiles, byId, incomplete, pathsByHash);
    }

    /// <summary>
    /// Gli hash dei download nelle code di Radarr e Sonarr (<c>downloadId</c>, senza badare a maiuscole): non ancora
    /// importati, anche un'alternativa leggera che aspetta l'import a mano, quindi mai Pulizia. Un servizio non configurato
    /// non ha coda; se una coda configurata non si legge gli hash sono null, con il codice dell'errore.
    /// </summary>
    private async Task<(HashSet<string>? Hashes, string? RadarrError, string? SonarrError)> QueuedHashesAsync(CancellationToken ct)
    {
        var hashes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var errors = new Dictionary<ArrKind, string>();
        foreach (var kind in new[] { ArrKind.Radarr, ArrKind.Sonarr })
        {
            try
            {
                hashes.UnionWith((await arr.GetQueueAsync(kind, ct).ConfigureAwait(false)).Select(q => q?.DownloadId).OfType<string>());
            }
            catch (ArrException ex) when (ex.Error != ArrError.NotConfigured)
            {
                errors[kind] = UpcomingErrors.Code(ex.Error);
            }
            catch (ArrException)
            {
                // Non configurato: nessuna coda.
            }
        }

        return (errors.Count == 0 ? hashes : null, errors.GetValueOrDefault(ArrKind.Radarr), errors.GetValueOrDefault(ArrKind.Sonarr));
    }

    // Il nome di un file di qBittorrent è relativo a save_path; i percorsi del seedbox sono Linux.
    private static string PathOf(QbitTorrent torrent, string name) => (torrent.SavePath ?? "").TrimEnd('/') + "/" + name;

    /// <summary>
    /// Toglie dalla coda di Radarr/Sonarr i download del titolo, senza blocklist (decisione 13). Uno ancora in download
    /// va via anche da qBittorrent; uno finito resta, e lo toglie <c>RemoveTorrents</c> o lo mette in attesa secondo la
    /// regola del seed. Una voce già uscita dalla coda (404) si salta.
    /// </summary>
    private async Task<StepResult> RemoveFromQueueAsync(Run run, CancellationToken ct)
    {
        var kind = run.Kind == SpaceKinds.Movie ? ArrKind.Radarr : ArrKind.Sonarr;
        var mine = (await arr.GetQueueAsync(kind, ct).ConfigureAwait(false))
            .OfType<ArrQueueItem>()
            .Where(q => run.Kind switch
            {
                SpaceKinds.Movie => q.MovieId == run.ArrId,
                SpaceKinds.Series => q.SeriesId == run.ArrId,
                _ => q.SeriesId == run.ArrId && q.SeasonNumber == run.Season,
            })
            .ToList();
        var removed = 0;
        foreach (var item in mine)
        {
            try
            {
                await arr.RemoveFromQueueAsync(kind, item.Id, blocklist: false, removeFromClient: item.Sizeleft > 0, ct).ConfigureAwait(false);
                removed++;
            }
            catch (ArrException ex) when (ex.Status == 404)
            {
                // Uscita dalla coda nel frattempo.
            }
        }

        return StepResult.Ok(removed);
    }

    private async Task<StepResult> DeleteEpisodeFilesAsync(Run run, CancellationToken ct)
    {
        var ids = (await arr.GetEpisodeFilesAsync(run.ArrId, ct).ConfigureAwait(false))
            .Where(f => f?.SeasonNumber == run.Season)
            .Select(f => f!.Id)
            .ToList();
        if (ids.Count == 0)
        {
            return StepResult.Skipped(SpaceDetails.Gone);
        }

        await arr.DeleteEpisodeFilesAsync(ids, ct).ConfigureAwait(false);
        return StepResult.Ok(ids.Count);
    }

    /// <summary>
    /// I torrent del titolo: quelli che si possono togliere ora vanno via (con i file, se nessun torrent che resta ha i loro
    /// percorsi), gli altri in attesa di fine seed (spec U §6.3).
    /// </summary>
    private async Task<StepResult> RemoveTitleTorrentsAsync(Run run, CancellationToken ct)
    {
        if (run.Estimate is not { } estimate)
        {
            return StepResult.Skipped(SpaceDetails.NotConfigured);
        }

        // Dal vivo: un torrent apparso dopo FindTorrents sullo stesso percorso deve tenere i suoi dati.
        await DeleteTorrentsAsync(estimate.RemoveNow, await ReadTorrentsAsync(ct).ConfigureAwait(false), ct).ConfigureAwait(false);
        var now = time.GetUtcNow();
        lock (_lock)
        {
            foreach (var torrent in estimate.RemoveLater.Select(hash => run.Facts[hash]))
            {
                Book.AddPending(new PendingTorrent
                {
                    Hash = torrent.Hash,
                    Name = torrent.Name,
                    Tracker = torrent.TrackerHost,
                    SizeBytes = torrent.SizeBytes,
                    ExpectedAt = SeedRule.Check(torrent, settings.Seed, now).ExpectedAt,
                    Title = run.Title,
                });
            }
        }

        return StepResult.Ok(estimate.RemoveNow.Count, estimate.RemoveLater.Count);
    }

    /// <summary>
    /// Pulizia (spec U §6.2): un torrent, o tutti i torrent "solo torrent" del calcolo. Dal vivo devono essere ancora
    /// senza copia in libreria, fuori dalle code di Radarr/Sonarr, finiti, e la regola del seed deve lasciarli togliere.
    /// </summary>
    private async Task<StepResult> RemoveCleanupTorrentsAsync(Run run, CancellationToken ct)
    {
        var wanted = run.Kind == SpaceKinds.Torrent ? new HashSet<string> { run.Key[TorrentPrefix.Length..] } : run.Scan.Torrents.Keys.ToHashSet();
        var (queued, radarrError, sonarrError) = await QueuedHashesAsync(ct).ConfigureAwait(false);
        if (queued is null)
        {
            // Senza le code non si sa quali download aspettano l'import: non si toglie nulla.
            return StepResult.Failed(radarrError ?? sonarrError ?? SpaceDetails.Unreachable);
        }

        var live = await ReadTorrentsAsync(ct).ConfigureAwait(false);
        var links = live.ById.ToDictionary(p => p.Key, p => p.Value.Links);
        var now = time.GetUtcNow();
        var torrentOnly = live.Index.Torrents
            .Where(t => wanted.Contains(t.Hash) && !queued.Contains(t.Hash) && SpaceMath.IsTorrentOnly(t.Hash, live.Index, links))
            .ToList();
        var removable = torrentOnly.Where(t => t.Progress >= 1 && SeedRule.Check(t, settings.Seed, now).CanRemoveNow).ToList();
        if (run.Kind == SpaceKinds.Torrent && removable.Count == 0)
        {
            // Sparito, o non più "solo torrent" (ora ha un hardlink in libreria): quello che la Pulizia mostrava non c'è più, quindi Gone.
            return StepResult.Skipped(torrentOnly.Count == 0 ? SpaceDetails.Gone : SpaceDetails.SeedRule);
        }

        var withFiles = await DeleteTorrentsAsync([.. removable.Select(t => t.Hash)], live, ct).ConfigureAwait(false);
        run.Removed = [.. removable.Select(t => t.Hash)];
        run.Freed = FreedBy(withFiles, live);
        return StepResult.Ok(removable.Count);
    }

    /// <summary>Toglie il media da Seerr, così il titolo torna richiedibile (spec U §6.2).</summary>
    private async Task<StepResult> RemoveFromSeerrAsync(Run run, CancellationToken ct)
    {
        if (!seerrSettings.IsConfigured())
        {
            return StepResult.Skipped(SpaceDetails.NotConfigured);
        }

        var tmdbId = run.Scanned?.TmdbId ?? 0;
        var mediaId = tmdbId > 0
            ? await seerr.FindMediaIdAsync(run.Kind == SpaceKinds.Movie ? "movie" : "tv", tmdbId, ct).ConfigureAwait(false)
            : null;
        if (mediaId is null)
        {
            return StepResult.Skipped(SpaceDetails.Gone);
        }

        await seerr.DeleteMediaAsync(mediaId.Value, ct).ConfigureAwait(false);
        return StepResult.Ok();
    }

    private Task<StepResult> Refresh()
    {
        library.Refresh();
        return Task.FromResult(StepResult.Ok());
    }

    /// <summary>
    /// Cancella un file orfano (sotto le cartelle di Pulizia) o un doppione (sotto la cartella del suo titolo, letta dal
    /// vivo) (spec U §6.2). Il servizio controlla da sé che il percorso stia sotto le radici, prima di chiamare il disco.
    /// </summary>
    private async Task<StepResult> DeleteFileAsync(Run run, CancellationToken ct)
    {
        var file = run.Scan.Files[run.Key];
        IReadOnlyList<string> roots = settings.ScanFolders;
        if (run.Kind == SpaceKinds.Duplicate)
        {
            if (file.OwnerKey is null)
            {
                return StepResult.Failed(SpaceDetails.Failed);
            }

            // Dopo il calcolo Radarr/Sonarr possono averlo preso come file del titolo (un upgrade): non è più un doppione.
            var (folder, known) = await OwnerAsync(file.OwnerKey, file.Path, ct).ConfigureAwait(false);
            if (known || string.IsNullOrWhiteSpace(folder))
            {
                return StepResult.Failed(SpaceDetails.Failed);
            }

            roots = [folder];
        }

        if (!FileProbe.IsUnder(file.Path, roots))
        {
            return StepResult.Failed(SpaceDetails.Failed);
        }

        if (run.Kind == SpaceKinds.Orphan)
        {
            var now = (await probe.StatAsync([file.Path], ct).ConfigureAwait(false)).GetValueOrDefault(file.Path);
            if (now is null)
            {
                return StepResult.Skipped(SpaceDetails.Gone);
            }

            // Un altro hardlink (libreria o torrent) o un file diverso da quello del calcolo: non è più l'orfano mostrato.
            if (now.Links > 1 || now.SizeBytes != file.SizeBytes)
            {
                return StepResult.Failed(SpaceDetails.Failed);
            }
        }

        if (!probe.Delete(file.Path, roots))
        {
            return StepResult.Failed(SpaceDetails.Failed);
        }

        run.Freed = file.SizeBytes;
        return StepResult.Ok();
    }

    /// <summary>La cartella del titolo dal vivo, e se il percorso è oggi il file del film o un file di episodio della serie.</summary>
    private async Task<(string? Folder, bool Known)> OwnerAsync(string ownerKey, string path, CancellationToken ct)
    {
        var parts = ownerKey.Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var id))
        {
            return (null, true);
        }

        if (parts[0] == "movie")
        {
            var movie = await arr.GetMovieAsync(id, ct).ConfigureAwait(false);
            return (movie.Path, movie.MovieFile?.Path == path);
        }

        // Come Radarr per un film che non c'è: la serie è sparita, il passo è saltato con Gone.
        var series = (await arr.GetSeriesAsync(ct).ConfigureAwait(false)).FirstOrDefault(s => s?.Id == id)
            ?? throw new ArrException(ArrError.Unreachable, status: 404);
        var files = await arr.GetEpisodeFilesAsync(id, ct).ConfigureAwait(false);
        return (series.Path, files.Any(f => f?.Path == path));
    }

    private StepResult ReadQuotaStep(Run run)
    {
        var quota = ReadQuota();
        run.QuotaAfter = QuotaAfter(quota, run.StartedAt);
        var step = QuotaStep(quota);
        return new StepResult(step.State, step.Detail);
    }

    /// <summary>
    /// I torrent letti dal vivo: indice, file in libreria, <c>stat</c> per id, il <c>content_path</c> dei torrent ancora
    /// in download (spec U §5.3: i loro file, anche in una cartella temporanea, non sono orfani) e tutti i percorsi di ogni
    /// torrent, anche quelli che <c>stat</c> non vede.
    /// </summary>
    private sealed record LiveTorrents(
        TorrentIndex Index,
        HashSet<FileId> LibraryFiles,
        IReadOnlyDictionary<FileId, FileStamp> ById,
        IReadOnlyList<string> IncompleteRoots,
        IReadOnlyDictionary<string, IReadOnlyList<string>> PathsByHash);

    /// <summary>
    /// Toglie i torrent da qBittorrent (spec U §6.3): con i file quelli i cui percorsi sono solo loro, senza file quelli che
    /// condividono un percorso con un torrent che resta (cross-seed). Restituisce quelli tolti con i file.
    /// </summary>
    private async Task<IReadOnlyList<string>> DeleteTorrentsAsync(IReadOnlyCollection<string> hashes, LiveTorrents live, CancellationToken ct)
    {
        var shared = SpaceMath.SharedWithStaying(hashes, live.PathsByHash);
        List<string> withFiles = [.. hashes.Where(h => !shared.Contains(h))];
        await qbit.DeleteAsync(withFiles, true, ct).ConfigureAwait(false);
        await qbit.DeleteAsync([.. hashes.Where(shared.Contains)], false, ct).ConfigureAwait(false);
        return withFiles;
    }

    /// <summary>I byte dei file (distinti) dei torrent tolti con i file: un file condiviso tra due di loro conta una volta.</summary>
    private static long FreedBy(IEnumerable<string> withFiles, LiveTorrents live) =>
        withFiles
            .SelectMany(hash => live.Index.FilesByHash.GetValueOrDefault(hash) ?? [])
            .Select(f => f.Id)
            .Distinct()
            .Sum(id => live.ById.TryGetValue(id, out var stamp) ? stamp.SizeBytes : 0);
}
