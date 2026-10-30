using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Un file su disco: id (device e inode), numero di hardlink e dimensione (spec U §12).</summary>
public sealed record FileStamp(FileId Id, int Links, long SizeBytes);

/// <summary>L'accesso al disco del seedbox: <c>stat</c>, elenco dei video, cancellazione sicura e lettura di un testo (spec U §12).</summary>
public interface IFileProbe
{
    /// <summary>
    /// Id, hardlink e dimensione dei percorsi. I file che non ci sono mancano dal risultato.
    /// Se un gruppo non risponde in tempo lancia <see cref="TimeoutException"/> (senza percorsi nel messaggio): i file non vanno trattati come mancanti.
    /// </summary>
    Task<IReadOnlyDictionary<string, FileStamp>> StatAsync(IReadOnlyList<string> paths, CancellationToken ct);

    /// <summary>I file video sopra <see cref="FileProbe.MinVideoBytes"/> sotto <paramref name="root"/>, ricorsivo; le cartelle illeggibili si saltano.</summary>
    IReadOnlyList<string> VideoFiles(string root);

    /// <summary>
    /// Cancella il file e le cartelle rimaste vuote, risalendo fino alla radice esclusa.
    /// Falso, senza cancellare, se il percorso non sta sotto una radice o contiene <c>..</c>.
    /// </summary>
    bool Delete(string path, IReadOnlyList<string> allowedRoots);

    /// <summary>Il testo del file, null se non si legge.</summary>
    string? ReadText(string path);

    /// <summary>L'ultima scrittura del file (UTC), null se non c'è.</summary>
    DateTimeOffset? LastWriteTime(string path);
}

/// <summary>Costanti e funzioni pure per i file del seedbox (spec U §12).</summary>
public static class FileProbe
{
    /// <summary>Sotto questa dimensione un file non è un film o un episodio (sample, trailer, ...): 100 MB.</summary>
    public const long MinVideoBytes = 100_000_000;

    /// <summary>Le estensioni che contano come video, minuscole.</summary>
    public static readonly IReadOnlySet<string> VideoExtensions =
        new HashSet<string>([".mkv", ".mp4", ".avi", ".m4v", ".ts"], StringComparer.OrdinalIgnoreCase);

    /// <summary>Le righe <c>dev\tino\tlinks\tsize\tpath</c> dell'output di <c>stat</c>; quelle rotte si saltano.</summary>
    public static IReadOnlyDictionary<string, FileStamp> ParseStat(string output)
    {
        var result = new Dictionary<string, FileStamp>();
        foreach (var line in output.Split('\n'))
        {
            var f = line.TrimEnd('\r').Split('\t', 5);
            if (f.Length == 5
                && f[4].Length > 0
                && long.TryParse(f[0], NumberStyles.None, CultureInfo.InvariantCulture, out var dev)
                && long.TryParse(f[1], NumberStyles.None, CultureInfo.InvariantCulture, out var ino)
                && int.TryParse(f[2], NumberStyles.None, CultureInfo.InvariantCulture, out var links)
                && long.TryParse(f[3], NumberStyles.None, CultureInfo.InvariantCulture, out var size))
            {
                result[f[4]] = new FileStamp(new FileId(dev, ino), links, size);
            }
        }

        return result;
    }

    /// <summary>
    /// Vero se il percorso, senza segmenti <c>..</c>, è una radice o sta sotto una di esse (confronto ordinale).
    /// Un percorso relativo e le radici vuote o a livello di disco (<c>/</c>) non contano. Da chiamare prima di ogni cancellazione.
    /// </summary>
    // shortcut: symlinks are not resolved (text comparison only), upgrade if a root ever contains symlinked folders
    public static bool IsUnder(string path, IReadOnlyList<string> roots)
    {
        if (string.IsNullOrWhiteSpace(path)
            || !Path.IsPathRooted(path)
            || path.Split('/', '\\').Contains(".."))
        {
            return false;
        }

        var full = Normalize(path);
        return roots.Select(Normalize).Any(r => r.Length > 0
            && (full == r || full.StartsWith(r + Path.DirectorySeparatorChar, StringComparison.Ordinal)));
    }

    /// <summary>Percorso assoluto senza separatore finale; vuoto per una radice vuota o per la radice del disco.</summary>
    internal static string Normalize(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "";
        }

        var full = Path.GetFullPath(path);
        return full.Length == Path.GetPathRoot(full)?.Length ? "" : full.TrimEnd('/', '\\');
    }
}
