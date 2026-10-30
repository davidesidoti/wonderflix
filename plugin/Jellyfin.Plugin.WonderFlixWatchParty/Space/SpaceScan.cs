using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// Un film, una serie o una stagione del calcolo (spec U §5.1). <c>Files</c> sono i file del titolo e <c>Hashes</c> i
/// torrent che la stima del calcolo ha legato al titolo: servono a ritrovarli quando Radarr/Sonarr hanno già tolto i file,
/// e solo quei torrent possono andare via così.
/// </summary>
public sealed record ScanTitle(string Title, int TmdbId, string? FolderPath, IReadOnlyList<FileFact> Files, IReadOnlyList<string> Hashes);

/// <summary>
/// Un file orfano o doppione del calcolo (spec U §5.3). <c>Kind</c> è <see cref="SpaceKinds.Orphan"/> o
/// <see cref="SpaceKinds.Duplicate"/>; per un doppione <c>OwnerKey</c> è il titolo (<c>movie:12</c> o <c>series:5</c>),
/// la cui cartella, letta dal vivo da Radarr/Sonarr, è l'unica dove si può cancellare.
/// </summary>
public sealed record ScanFile(string Path, string Kind, long SizeBytes, string? OwnerKey = null);

/// <summary>
/// Una riga di una lista del calcolo (spec U §4.2): la nasconde chi tiene una delle <c>Keys</c> (la riga o la sua serie)
/// e chi ha tra i preferiti uno degli <c>ItemIds</c> di Jellyfin.
/// </summary>
public sealed record ScanRow<T>(T Dto, IReadOnlyList<string> Keys, IReadOnlyList<Guid> ItemIds);

/// <summary>L'ultimo calcolo (spec U §5 e §7.3): le liste per la panoramica e quello che serve alle operazioni.</summary>
public sealed record SpaceScan
{
    /// <summary>Quando è finito; null nei calcoli fatti a mano dei test.</summary>
    public DateTimeOffset? ScannedAt { get; init; }

    public SpaceQuotaDto? Quota { get; init; }

    public SpaceBreakdownDto Breakdown { get; init; } = new(0, 0, 0, 0, 0);

    /// <summary>In ordine (Global Constraints), prima di togliere tenuti e preferiti.</summary>
    public IReadOnlyList<ScanRow<SpaceCandidateDto>> Delete { get; init; } = [];

    public IReadOnlyList<ScanRow<SpaceLightenDto>> Lighten { get; init; } = [];

    public SpaceCleanupDto Cleanup { get; init; } = new([], [], []);

    public SpaceErrorsDto Errors { get; init; } = new(null, null, null, null, null);

    /// <summary>Gli id Jellyfin di film e stagioni, per i voti alti di chi chiama (decisione 14).</summary>
    public IReadOnlyList<Guid> RatedItems { get; init; } = [];

    /// <summary>Per chiave: <c>movie:{id}</c>, <c>series:{id}</c>, <c>season:{id}:{n}</c>.</summary>
    public IReadOnlyDictionary<string, ScanTitle> Titles { get; init; } = new Dictionary<string, ScanTitle>();

    /// <summary>Per chiave <c>file:{h}</c>.</summary>
    public IReadOnlyDictionary<string, ScanFile> Files { get; init; } = new Dictionary<string, ScanFile>();

    /// <summary>I torrent senza copia in libreria (Pulizia), per hash.</summary>
    public IReadOnlyDictionary<string, TorrentFacts> Torrents { get; init; } = new Dictionary<string, TorrentFacts>();
}
