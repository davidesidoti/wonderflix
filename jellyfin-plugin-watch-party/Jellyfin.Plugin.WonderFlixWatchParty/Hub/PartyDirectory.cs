using System.Security.Cryptography;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un party registrato, come lo legge chi lo chiede.</summary>
public sealed record PartyView(Guid GroupId, Guid CreatorId, string Mode, string? Code);

/// <summary>
/// Party registrati, in RAM (spec F §6.4–6.6): modalità, codici dei privati,
/// invitati e da quando il plugin vede i gruppi non registrati. Vivono
/// quanto i gruppi SyncPlay. Sicuro tra thread.
/// </summary>
public sealed class PartyDirectory(TimeProvider time)
{
    /// <summary>Un gruppo mai registrato diventa pubblico dopo questa attesa.</summary>
    public static readonly TimeSpan UnregisteredGrace = TimeSpan.FromSeconds(10);

    public const int CodeLength = 6;

    /// <summary>Simboli dei codici: niente 0/O/1/I/L, che si confondono.</summary>
    public const string CodeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Entry> _parties = [];
    private readonly Dictionary<string, Guid> _codes = new(StringComparer.Ordinal);
    private readonly Dictionary<Guid, DateTimeOffset> _firstSeen = [];

    /// <summary>Registra il party; null se lo era già. I privati hanno un codice.</summary>
    public PartyView? Register(Guid groupId, Guid creatorId, string mode)
    {
        lock (_lock)
        {
            if (_parties.ContainsKey(groupId))
            {
                return null;
            }

            string? code = null;
            if (mode == PartyModes.Private)
            {
                do
                {
                    code = RandomNumberGenerator.GetString(CodeAlphabet, CodeLength);
                }
                while (_codes.ContainsKey(code));

                _codes[code] = groupId;
            }

            var entry = new Entry(creatorId, mode, code);
            _parties[groupId] = entry;
            return entry.View(groupId);
        }
    }

    public PartyView? Get(Guid groupId)
    {
        lock (_lock)
        {
            return _parties.TryGetValue(groupId, out var entry) ? entry.View(groupId) : null;
        }
    }

    /// <summary>Il plugin vede il gruppo in un elenco: per uno non registrato parte l'attesa.</summary>
    public void Seen(Guid groupId)
    {
        lock (_lock)
        {
            _firstSeen.TryAdd(groupId, time.GetUtcNow());
        }
    }

    /// <summary>
    /// viewer può vedere il gruppo (spec F §6.4), a parte il caso
    /// "partecipante", che decide chi chiama. isFriendOfCreator si chiama
    /// fuori dal lock (va a chiedere agli amici).
    /// </summary>
    public bool IsVisible(Guid groupId, Guid viewer, Func<Guid, bool> isFriendOfCreator)
    {
        string mode;
        Guid creator;
        bool invited;
        lock (_lock)
        {
            if (!_parties.TryGetValue(groupId, out var entry))
            {
                return _firstSeen.TryGetValue(groupId, out var seen) && time.GetUtcNow() - seen >= UnregisteredGrace;
            }

            (mode, creator, invited) = (entry.Mode, entry.CreatorId, entry.Invited.Contains(viewer));
        }

        return mode == PartyModes.Public
            || invited
            || creator == viewer
            || (mode == PartyModes.Friends && isFriendOfCreator(creator));
    }

    /// <summary>Il gruppo del codice (maiuscole, spazi e trattini non contano); null se non c'è.</summary>
    public Guid? FindByCode(string? code)
    {
        var normalized = NormalizeCode(code);
        if (normalized is null)
        {
            return null;
        }

        lock (_lock)
        {
            return _codes.TryGetValue(normalized, out var groupId) ? groupId : null;
        }
    }

    /// <summary>Chi è invitato, o è entrato con il codice, vede il party.</summary>
    public void Grant(Guid groupId, IEnumerable<Guid> users)
    {
        lock (_lock)
        {
            if (_parties.TryGetValue(groupId, out var entry))
            {
                entry.Invited.UnionWith(users);
            }
        }
    }

    /// <summary>
    /// Toglie party e attese dei gruppi finiti (alive si chiama fuori dal
    /// lock: chiede a Jellyfin). Restituisce quanti party ha tolto.
    /// </summary>
    public int Forget(Func<Guid, bool> alive)
    {
        List<Guid> known;
        lock (_lock)
        {
            known = _parties.Keys.Concat(_firstSeen.Keys).Distinct().ToList();
        }

        var ended = known.Where(id => !alive(id)).ToList();
        var removed = 0;
        lock (_lock)
        {
            foreach (var id in ended)
            {
                if (_parties.Remove(id, out var entry))
                {
                    removed++;
                    if (entry.Code is not null)
                    {
                        _codes.Remove(entry.Code);
                    }
                }

                _firstSeen.Remove(id);
            }
        }

        return removed;
    }

    /// <summary>Il codice in forma canonica; null se non ha la lunghezza giusta.</summary>
    public static string? NormalizeCode(string? code)
    {
        if (code is null)
        {
            return null;
        }

        var normalized = string.Concat(code.Where(char.IsLetterOrDigit)).ToUpperInvariant();
        return normalized.Length == CodeLength ? normalized : null;
    }

    private sealed class Entry(Guid creatorId, string mode, string? code)
    {
        public Guid CreatorId { get; } = creatorId;

        public string Mode { get; } = mode;

        public string? Code { get; } = code;

        public HashSet<Guid> Invited { get; } = [];

        public PartyView View(Guid groupId) => new(groupId, CreatorId, Mode, Code);
    }
}
