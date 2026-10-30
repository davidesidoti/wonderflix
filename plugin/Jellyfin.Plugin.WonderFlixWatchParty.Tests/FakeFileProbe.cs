using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Disco finto: file in memoria, cancellazioni registrate e testi (spec U §12).</summary>
internal sealed class FakeFileProbe : IFileProbe
{
    /// <summary>I file che esistono, per percorso.</summary>
    public Dictionary<string, FileStamp> Files { get; } = [];

    /// <summary>Ogni chiamata a <see cref="Delete"/>, sempre, con le radici passate: il finto non filtra, così un test prova che il servizio controlla da sé.</summary>
    public List<(string Path, IReadOnlyList<string> Roots)> DeleteCalls { get; } = [];

    /// <summary>Il risultato di <see cref="Delete"/>; se falso il file resta.</summary>
    public bool DeleteResult { get; set; } = true;

    /// <summary>I percorsi cancellati davvero (chiamate con risultato vero), in ordine.</summary>
    public List<string> Deleted { get; } = [];

    /// <summary>I testi leggibili, per percorso.</summary>
    public Dictionary<string, string> Texts { get; } = [];

    /// <summary>L'ultima scrittura dei file, per percorso; un percorso che manca dà null.</summary>
    public Dictionary<string, DateTimeOffset> WriteTimes { get; } = [];

    /// <summary>Se impostato, <see cref="StatAsync"/> lancia questo errore (come un gruppo che non risponde in tempo).</summary>
    public Exception? StatFails { get; set; }

    public Task<IReadOnlyDictionary<string, FileStamp>> StatAsync(IReadOnlyList<string> paths, CancellationToken ct) =>
        StatFails is { } error
            ? Task.FromException<IReadOnlyDictionary<string, FileStamp>>(error)
            : Task.FromResult<IReadOnlyDictionary<string, FileStamp>>(
                paths.Where(Files.ContainsKey).Distinct().ToDictionary(p => p, p => Files[p]));

    public IReadOnlyList<string> VideoFiles(string root) =>
        [.. Files.Where(f => FileProbe.IsUnder(f.Key, [root])
            && FileProbe.VideoExtensions.Contains(Path.GetExtension(f.Key))
            && f.Value.SizeBytes > FileProbe.MinVideoBytes).Select(f => f.Key)];

    public bool Delete(string path, IReadOnlyList<string> allowedRoots)
    {
        DeleteCalls.Add((path, allowedRoots));
        if (!DeleteResult)
        {
            return false;
        }

        Files.Remove(path);
        Deleted.Add(path);
        return true;
    }

    public string? ReadText(string path) => Texts.GetValueOrDefault(path);

    public DateTimeOffset? LastWriteTime(string path) => WriteTimes.TryGetValue(path, out var at) ? at : null;
}
