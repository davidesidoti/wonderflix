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

        // Nuovo tentativo dopo che Radarr/Sonarr hanno tolto i file: valgono gli id del calcolo, che i torrent tengono vivi.
        IReadOnlyList<FileFact> files = stamps.Count > 0
            ? [.. stamps.Select(p => new FileFact(p.Key, p.Value.Id, p.Value.Links, p.Value.SizeBytes))]
            : run.Scanned?.Files ?? [];
        var (index, libraryFiles) = await ReadTorrentsAsync(ct).ConfigureAwait(false);
        var estimate = SpaceMath.Estimate(files, index, libraryFiles, settings.Seed, time.GetUtcNow());
        run.Estimate = estimate;
        run.Facts = index.Torrents.ToDictionary(t => t.Hash);
        (run.Freed, run.Pending) = (estimate.FreeNowBytes, estimate.FreeLaterBytes);
        return StepResult.Ok(estimate.RemoveNow.Count, estimate.RemoveLater.Count);
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
    /// I torrent di qBittorrent con i loro file su disco, e i file che hanno un hardlink fuori dai torrent: quelli in libreria.
    /// I file che non sono su disco restano fuori dall'indice.
    /// </summary>
    private async Task<(TorrentIndex Index, HashSet<FileId> LibraryFiles)> ReadTorrentsAsync(CancellationToken ct)
    {
        var facts = new List<TorrentFacts>();
        var paths = new Dictionary<string, List<string>>();
        foreach (var torrent in await qbit.GetTorrentsAsync(ct).ConfigureAwait(false))
        {
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
        return (new TorrentIndex(facts, filesByHash), libraryFiles);
    }

    // Il nome di un file di qBittorrent è relativo a save_path; i percorsi del seedbox sono Linux.
    private static string PathOf(QbitTorrent torrent, string name) => (torrent.SavePath ?? "").TrimEnd('/') + "/" + name;

    /// <summary>Toglie dalla coda di Radarr/Sonarr i download del titolo, senza blocklist (decisione 13).</summary>
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
        foreach (var item in mine)
        {
            await arr.RemoveFromQueueAsync(kind, item.Id, blocklist: false, ct).ConfigureAwait(false);
        }

        return StepResult.Ok(mine.Count);
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

    /// <summary>I torrent del titolo: quelli che si possono togliere ora vanno via con i file, gli altri in attesa di fine seed (spec U §6.3).</summary>
    private async Task<StepResult> RemoveTitleTorrentsAsync(Run run, CancellationToken ct)
    {
        if (run.Estimate is not { } estimate)
        {
            return StepResult.Skipped(SpaceDetails.NotConfigured);
        }

        await qbit.DeleteAsync(estimate.RemoveNow, ct).ConfigureAwait(false);
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
    /// Pulizia (spec U §6.2): un torrent, o tutti i torrent "solo torrent" del calcolo, se la regola del seed dal vivo
    /// li lascia togliere. Un torrent singolo ancora in seed obbligatorio è saltato con <c>SeedRule</c>.
    /// </summary>
    private async Task<StepResult> RemoveCleanupTorrentsAsync(Run run, CancellationToken ct)
    {
        var wanted = run.Kind == SpaceKinds.Torrent ? new HashSet<string> { run.Key[TorrentPrefix.Length..] } : run.Scan.Torrents.Keys.ToHashSet();
        var now = time.GetUtcNow();
        var found = 0;
        var removable = new List<TorrentFacts>();
        foreach (var torrent in await qbit.GetTorrentsAsync(ct).ConfigureAwait(false))
        {
            if (torrent.Hash is null || !wanted.Remove(torrent.Hash))
            {
                continue;
            }

            found++;
            var facts = await FactsAsync(torrent, ct).ConfigureAwait(false);
            if (SeedRule.Check(facts, settings.Seed, now).CanRemoveNow)
            {
                removable.Add(facts);
            }
        }

        if (run.Kind == SpaceKinds.Torrent && removable.Count == 0)
        {
            return StepResult.Skipped(found == 0 ? SpaceDetails.Gone : SpaceDetails.SeedRule);
        }

        await qbit.DeleteAsync([.. removable.Select(t => t.Hash)], ct).ConfigureAwait(false);
        run.Freed = removable.Sum(t => t.SizeBytes);
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
    /// Cancella un file orfano (sotto le cartelle di Pulizia) o un doppione (sotto la cartella del suo titolo) (spec U §6.2).
    /// Il servizio controlla da sé che il percorso stia sotto le radici, prima di chiamare il disco.
    /// </summary>
    private async Task<StepResult> DeleteFileAsync(Run run, CancellationToken ct)
    {
        var file = run.Scan.Files[run.Key];
        IReadOnlyList<string> roots = settings.ScanFolders;
        if (run.Kind == SpaceKinds.Duplicate)
        {
            if (file.OwnerKey is null || string.IsNullOrWhiteSpace(file.OwnerFolder))
            {
                return StepResult.Failed(SpaceDetails.Failed);
            }

            // Dopo il calcolo Radarr/Sonarr possono averlo preso come file del titolo (un upgrade): non è più un doppione.
            if (await KnownByArrAsync(file.OwnerKey, file.Path, ct).ConfigureAwait(false))
            {
                return StepResult.Failed(SpaceDetails.Failed);
            }

            roots = [file.OwnerFolder];
        }

        if (!FileProbe.IsUnder(file.Path, roots) || !probe.Delete(file.Path, roots))
        {
            return StepResult.Failed(SpaceDetails.Failed);
        }

        run.Freed = file.SizeBytes;
        return StepResult.Ok();
    }

    // Vero se il percorso è oggi il file del film o un file di episodio della serie.
    private async Task<bool> KnownByArrAsync(string ownerKey, string path, CancellationToken ct)
    {
        var parts = ownerKey.Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var id))
        {
            return true;
        }

        return parts[0] == "movie"
            ? (await arr.GetMovieAsync(id, ct).ConfigureAwait(false)).MovieFile?.Path == path
            : (await arr.GetEpisodeFilesAsync(id, ct).ConfigureAwait(false)).Any(f => f?.Path == path);
    }

    private StepResult ReadQuotaStep(Run run)
    {
        var quota = ReadQuota();
        run.QuotaAfter = quota?.UsedBytes;
        var step = QuotaStep(quota);
        return new StepResult(step.State, step.Detail);
    }
}
