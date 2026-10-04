namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un'ondata di nuovi titoli (spec G §6.6): gli id aggiunti e tolti, gli id
/// esterni di quelli tolti, i tempi e le chiusure non riuscite. Solo id, mai
/// elementi di Jellyfin. Non è sicura tra thread: la usa solo
/// NewTitlesCollector, sotto lock.
/// </summary>
public sealed class NewTitlesWave(DateTimeOffset startedAt)
{
    private readonly HashSet<Guid> _added = [];

    // Gli id tolti: servono quando un'ondata più vecchia assorbe questa.
    private readonly HashSet<Guid> _removedIds = [];
    private readonly List<(bool IsMovie, HashSet<string> Keys)> _removed = [];

    private int _failedCloses;

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
        _removedIds.Add(itemId);
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

    /// <summary>
    /// Questa ondata (staccata, con la chiusura non riuscita) torna in corso e
    /// prende quello che è arrivato nel frattempo nell'ondata più nuova. Resta
    /// l'inizio di questa: il tetto di attesa conta dal primo titolo.
    /// </summary>
    public void Absorb(NewTitlesWave newer)
    {
        // Prima i tolti e poi gli aggiunti: un titolo tolto e rimesso nella nuova resta.
        _added.ExceptWith(newer._removedIds);
        _added.UnionWith(newer._added);
        _removedIds.UnionWith(newer._removedIds);
        _removed.AddRange(newer._removed);
        if (newer.LastChangeAt > LastChangeAt)
        {
            LastChangeAt = newer.LastChangeAt;
        }
    }

    /// <summary>Conta una chiusura non riuscita; restituisce quante finora.</summary>
    public int RecordFailedClose() => ++_failedCloses;

    public bool IsQuiet(DateTimeOffset now, TimeSpan quiet) => now - LastChangeAt >= quiet;

    public bool IsOverdue(DateTimeOffset now, TimeSpan maxWait) => now - StartedAt >= maxWait;
}
