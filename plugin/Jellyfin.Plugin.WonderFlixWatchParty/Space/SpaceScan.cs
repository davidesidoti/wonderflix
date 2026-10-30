namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// Un film, una serie o una stagione del calcolo (spec U §5.1). <c>Files</c> sono i file del titolo come
/// li ha visti il calcolo: servono a ritrovare i torrent quando Radarr/Sonarr hanno già tolto i file.
/// </summary>
public sealed record ScanTitle(string Title, int TmdbId, string? FolderPath, IReadOnlyList<FileFact> Files);

/// <summary>
/// Un file orfano o doppione del calcolo (spec U §5.3). <c>Kind</c> è <see cref="SpaceKinds.Orphan"/> o
/// <see cref="SpaceKinds.Duplicate"/>; per un doppione <c>OwnerKey</c> è il titolo (<c>movie:12</c> o
/// <c>series:5</c>) e <c>OwnerFolder</c> la sua cartella in Radarr/Sonarr, l'unica dove si può cancellare.
/// </summary>
public sealed record ScanFile(string Path, string Kind, long SizeBytes, string? OwnerKey = null, string? OwnerFolder = null);

/// <summary>L'ultimo calcolo, per quello che serve alle operazioni (spec U §6.2 e §7.3). Il Task 10 lo completa.</summary>
public sealed record SpaceScan
{
    /// <summary>Per chiave: <c>movie:{id}</c>, <c>series:{id}</c>, <c>season:{id}:{n}</c>.</summary>
    public IReadOnlyDictionary<string, ScanTitle> Titles { get; init; } = new Dictionary<string, ScanTitle>();

    /// <summary>Per chiave <c>file:{h}</c>.</summary>
    public IReadOnlyDictionary<string, ScanFile> Files { get; init; } = new Dictionary<string, ScanFile>();

    /// <summary>I torrent senza copia in libreria (Pulizia), per hash.</summary>
    public IReadOnlyDictionary<string, TorrentFacts> Torrents { get; init; } = new Dictionary<string, TorrentFacts>();
}
