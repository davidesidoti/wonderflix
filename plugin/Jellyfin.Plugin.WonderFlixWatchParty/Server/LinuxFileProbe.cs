using System.Diagnostics;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Il disco del seedbox: <c>/usr/bin/stat</c> in un processo, elenco e cancellazione con <c>System.IO</c> (spec U §12).</summary>
public sealed class LinuxFileProbe : IFileProbe
{
    private const string StatPath = "/usr/bin/stat";

    /// <summary>Dev, inode, hardlink, dimensione e nome, separati da tab.</summary>
    private const string StatFormat = "%d\t%i\t%h\t%s\t%n\n";

    /// <summary>Quanti percorsi per ogni chiamata di <c>stat</c>, per non superare il limite degli argomenti.</summary>
    private const int StatBatch = 500;

    /// <summary>Oltre questo tempo un gruppo di <c>stat</c> si ferma (disco bloccato): 2 minuti.</summary>
    private static readonly TimeSpan StatTimeout = TimeSpan.FromMinutes(2);

    public async Task<IReadOnlyDictionary<string, FileStamp>> StatAsync(IReadOnlyList<string> paths, CancellationToken ct)
    {
        var result = new Dictionary<string, FileStamp>();
        foreach (var batch in paths.Chunk(StatBatch))
        {
            foreach (var (path, stamp) in await StatBatchAsync(batch, ct))
            {
                result[path] = stamp;
            }
        }

        return result;
    }

    public IReadOnlyList<string> VideoFiles(string root)
    {
        if (!Directory.Exists(root))
        {
            return [];
        }

        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true };
        var found = new List<string>();
        foreach (var file in new DirectoryInfo(root).EnumerateFiles("*", options))
        {
            if (FileProbe.VideoExtensions.Contains(file.Extension) && file.Length > FileProbe.MinVideoBytes)
            {
                found.Add(file.FullName);
            }
        }

        return found;
    }

    public bool Delete(string path, IReadOnlyList<string> allowedRoots)
    {
        if (!FileProbe.IsUnder(path, allowedRoots))
        {
            return false;
        }

        var roots = allowedRoots.Select(FileProbe.Normalize).Where(r => r.Length > 0).ToList();
        try
        {
            File.Delete(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return false;
        }

        // Il file è andato: se le cartelle vuote non si tolgono, il risultato resta vero.
        try
        {
            // Si risale finché la cartella è vuota; la radice stessa non si tocca mai.
            var dir = Path.GetDirectoryName(Path.GetFullPath(path));
            while (dir is not null
                && !roots.Contains(FileProbe.Normalize(dir))
                && FileProbe.IsUnder(dir, allowedRoots)
                && !Directory.EnumerateFileSystemEntries(dir).Any())
            {
                Directory.Delete(dir);
                dir = Path.GetDirectoryName(dir);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // cartella non vuota all'ultimo istante o non cancellabile: resta lì
        }

        return true;
    }

    public string? ReadText(string path)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static async Task<IReadOnlyDictionary<string, FileStamp>> StatBatchAsync(string[] batch, CancellationToken ct)
    {
        var info = new ProcessStartInfo(StatPath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        info.ArgumentList.Add("--printf");
        info.ArgumentList.Add(StatFormat);
        info.ArgumentList.Add("--");
        foreach (var path in batch)
        {
            info.ArgumentList.Add(path);
        }

        using var process = Process.Start(info) ?? throw new IOException("stat non parte");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(StatTimeout);

        // Le letture dalle pipe non rispettano il token: partono senza e finiscono quando il processo chiude l'output.
        var output = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
        var errors = process.StandardError.ReadToEndAsync(CancellationToken.None); // svuotato: stat si lamenta dei file mancanti
        try
        {
            await process.WaitForExitAsync(timeout.Token); // il codice d'uscita 1 (file mancanti) non conta
        }
        catch (OperationCanceledException)
        {
            // Si ferma solo questo processo, mai per nome.
            try
            {
                process.Kill();
            }
            catch (InvalidOperationException)
            {
                // già finito
            }

            ct.ThrowIfCancellationRequested();
            throw new TimeoutException("stat scaduto");
        }

        await Task.WhenAll(output, errors);
        return FileProbe.ParseStat(output.Result);
    }
}
