namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un'ondata di nuovi titoli (spec G §6.6): gli id aggiunti, gli id esterni
/// di quelli tolti e i tempi. Solo id, mai elementi di Jellyfin. Non è sicura
/// tra thread: la usa solo NewTitlesCollector, sotto lock.
/// </summary>
public sealed class NewTitlesWave(DateTimeOffset startedAt)
{
    private readonly HashSet<Guid> _added = [];
    private readonly List<(bool IsMovie, HashSet<string> Keys)> _removed = [];

    public DateTimeOffset StartedAt { get; } = startedAt;

    /// <summary>L'ultima aggiunta o rimozione.</summary>
    public DateTimeOffset LastChangeAt { get; private set; } = startedAt;

    /// <summary>Titoli aggiunti (e non tolti) finora.</summary>
    public int Count => _added.Count;

    public IEnumerable<Guid> AddedIds => _added;

    public void Add(Guid itemId, DateTimeOffset now)
    {
        _added.Add(itemId);
        LastChangeAt = now;
    }

    /// <summary>
    /// Un titolo tolto: se era arrivato in questa ondata sparisce; i suoi id
    /// esterni fanno riconoscere chi lo sostituisce.
    /// </summary>
    public void Remove(Guid itemId, bool isMovie, IReadOnlyCollection<string> externalKeys, DateTimeOffset now)
    {
        _added.Remove(itemId);
        if (externalKeys.Count > 0)
        {
            _removed.Add((isMovie, new HashSet<string>(externalKeys, StringComparer.OrdinalIgnoreCase)));
        }

        LastChangeAt = now;
    }

    /// <summary>
    /// Il titolo sostituisce uno tolto in questa ondata: stesso tipo e almeno
    /// un id esterno in comune (es. un file migliore da Radarr o Sonarr).
    /// </summary>
    public bool IsReplacement(LibraryTitle title) =>
        _removed.Any(r => r.IsMovie == title.IsMovie && title.ExternalKeys.Any(r.Keys.Contains));

    public bool IsQuiet(DateTimeOffset now, TimeSpan quiet) => now - LastChangeAt >= quiet;

    public bool IsOverdue(DateTimeOffset now, TimeSpan maxWait) => now - StartedAt >= maxWait;
}
