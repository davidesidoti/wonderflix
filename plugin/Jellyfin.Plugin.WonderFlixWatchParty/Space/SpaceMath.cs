namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Un file su disco, identificato da device e inode: due percorsi con lo stesso id sono lo stesso file (spec U §12).</summary>
public readonly record struct FileId(long Device, long Inode);

/// <summary>Un file di un titolo: percorso, id, numero di hardlink e dimensione (spec U §5.1).</summary>
public sealed record FileFact(string Path, FileId Id, int Links, long SizeBytes);

/// <summary>Un file di un torrent: percorso e id (spec U §5.3).</summary>
public sealed record TorrentFile(string Path, FileId Id);

/// <summary>I torrent e i loro file, con l'indice inverso dal file ai torrent che lo contengono (spec U §11).</summary>
public sealed record TorrentIndex(IReadOnlyList<TorrentFacts> Torrents, IReadOnlyDictionary<string, IReadOnlyList<TorrentFile>> FilesByHash)
{
    /// <summary>Per ogni file gli hash dei torrent che lo contengono.</summary>
    public IReadOnlyDictionary<FileId, IReadOnlyList<string>> HashesByFile { get; } =
        FilesByHash
            .SelectMany(p => p.Value.Select(f => (f.Id, Hash: p.Key)))
            .GroupBy(x => x.Id)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<string>)g.Select(x => x.Hash).Distinct().ToList());
}

/// <summary>Quanto spazio libera togliere un titolo, e quali torrent (hash) vanno via con lui (spec U §5.1, §6.3 e §11).</summary>
public sealed record SpaceEstimate(
    long FreeNowBytes,
    long FreeLaterBytes,
    DateTimeOffset? FreeLaterAt,
    long InPackBytes,
    IReadOnlyList<string> RemoveNow,
    IReadOnlyList<string> RemoveLater);

/// <summary>La stima, in memoria, dello spazio liberato da un titolo (spec U §5.1).</summary>
public static class SpaceMath
{
    /// <summary>
    /// Per ogni file del titolo: se un hardlink sconosciuto o un torrent che serve ad altri file della libreria lo trattiene,
    /// i byte sono "nel pack"; altrimenti si liberano subito o quando scade il seed obbligatorio dei torrent che lo contengono.
    /// Se uno di quei torrent è ancora in download la data resta null.
    /// </summary>
    public static SpaceEstimate Estimate(
        IReadOnlyList<FileFact> titleFiles,
        TorrentIndex index,
        IReadOnlySet<FileId> libraryFiles,
        SeedSettings seed,
        DateTimeOffset now)
    {
        var titleIds = titleFiles.Select(f => f.Id).ToHashSet();
        var verdicts = index.Torrents.ToDictionary(t => t.Hash, t => SeedRule.Check(t, seed, now));
        var removeNow = new List<string>();
        var removeLater = new List<string>();
        long freeNow = 0, freeLater = 0, inPack = 0;
        DateTimeOffset? laterAt = null;
        var laterUnknown = false;

        foreach (var file in titleFiles)
        {
            var holders = index.HashesByFile.TryGetValue(file.Id, out var found) ? found : [];
            var known = 1 + DistinctPaths(file.Id, index).Count;
            var detachable = holders.All(hash => verdicts.ContainsKey(hash)
                && index.FilesByHash[hash].All(f => titleIds.Contains(f.Id) || !libraryFiles.Contains(f.Id)));
            if (file.Links > known || !detachable)
            {
                inPack += file.SizeBytes;
                continue;
            }

            var waiting = holders.Where(hash => !verdicts[hash].CanRemoveNow).ToList();
            if (waiting.Count == 0)
            {
                freeNow += file.SizeBytes;
            }
            else
            {
                freeLater += file.SizeBytes;
                foreach (var at in waiting.Select(hash => verdicts[hash].ExpectedAt))
                {
                    laterUnknown |= at is null;
                    laterAt = at is not null && (laterAt is null || at > laterAt) ? at : laterAt;
                }
            }

            foreach (var hash in holders)
            {
                var list = verdicts[hash].CanRemoveNow ? removeNow : removeLater;
                if (!list.Contains(hash))
                {
                    list.Add(hash);
                }
            }
        }

        return new SpaceEstimate(freeNow, freeLater, laterUnknown ? null : laterAt, inPack, removeNow, removeLater);
    }

    /// <summary>Vero se ogni file del torrent ha tanti hardlink quanti sono i percorsi distinti di torrent: nessun hardlink fuori dai torrent.</summary>
    public static bool IsTorrentOnly(string hash, TorrentIndex index, IReadOnlyDictionary<FileId, int> links) =>
        index.FilesByHash.TryGetValue(hash, out var files)
        && files.All(f => links.TryGetValue(f.Id, out var n) && n == DistinctPaths(f.Id, index).Count);

    /// <summary>I percorsi distinti, tra tutti i torrent, di un file: due torrent sullo stesso percorso contano una volta.</summary>
    private static HashSet<string> DistinctPaths(FileId id, TorrentIndex index) =>
        index.HashesByFile.TryGetValue(id, out var hashes)
            ? hashes.SelectMany(hash => index.FilesByHash[hash]).Where(f => f.Id == id).Select(f => f.Path).ToHashSet()
            : [];
}
