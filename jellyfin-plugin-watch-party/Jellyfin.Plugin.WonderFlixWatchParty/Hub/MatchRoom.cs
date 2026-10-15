using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Una sala del match (spec P §6.1, §6.3): membri, inviti, pila, voti, match
/// e quasi match. Solo dati e regole, senza lock: la usa
/// <c>MatchService</c> sotto il suo. I voti dei singoli non escono
/// mai: <see cref="Snapshot"/> ha solo i conteggi.
/// </summary>
public sealed class MatchRoom
{
    /// <summary>Membri al massimo, compreso chi ha aperto (spec P §3).</summary>
    public const int MaxMembers = 8;

    /// <summary>Membri per iniziare: chi ha aperto e almeno un amico.</summary>
    public const int MinMembers = 2;

    /// <summary>Quasi match al massimo (spec P §6.3).</summary>
    public const int MaxNearMatches = 5;

    private readonly List<Member> _members = [];
    private readonly HashSet<Guid> _invited = [];
    private readonly List<Guid> _stack = [];
    private readonly HashSet<Guid> _shown = [];
    private readonly Dictionary<Guid, Dictionary<Guid, bool>> _votes = [];
    private readonly List<Guid> _matches = [];

    public MatchRoom(Guid id, Guid creatorId, string creatorName, DateTimeOffset now)
    {
        Id = id;
        CreatorId = creatorId;
        CreatorName = creatorName;
        LastActivityAt = now;
        _members.Add(new Member(creatorId, creatorName));
    }

    public Guid Id { get; }

    public Guid CreatorId { get; }

    public string CreatorName { get; }

    public string Phase { get; private set; } = MatchPhases.Waiting;

    /// <summary>Cresce a ogni cambio visibile nello stato: l'app scarta gli stati più vecchi.</summary>
    public long Rev { get; private set; } = 1;

    /// <summary>Il plugin sta pescando titoli (Start o More): niente ingressi né altre pescate.</summary>
    public bool Drawing { get; set; }

    /// <summary>I filtri dell'inizio, per "Altri 30"; null in attesa.</summary>
    public MatchFilters? Filters { get; private set; }

    /// <summary>Apertura, ultimo ingresso o ultimo voto (spec P §6.1: 1 h senza attività chiude).</summary>
    public DateTimeOffset LastActivityAt { get; private set; }

    public DateTimeOffset? ClosedAt { get; private set; }

    public string? ClosedReason { get; private set; }

    public Guid? PartyGroupId { get; private set; }

    public bool IsOpen => Phase != MatchPhases.Closed;

    public IReadOnlyList<Guid> MemberIds => _members.Select(m => m.UserId).ToList();

    public int MemberCount => _members.Count;

    /// <summary>Tutti i titoli mai messi nella pila: "Altri 30" non li ripesca.</summary>
    public IReadOnlyCollection<Guid> Shown => _shown;

    /// <summary>In votazione, ogni membro ha votato tutta la pila (anche vuota).</summary>
    public bool AllFinished =>
        Phase == MatchPhases.Voting && _members.All(m => Voted(m.UserId) == _stack.Count);

    public bool IsMember(Guid userId) => _members.Any(m => m.UserId == userId);

    public void Invite(Guid userId) => _invited.Add(userId);

    /// <summary>
    /// Entra un invitato; restituisce il motivo del no (MatchReasons) o null.
    /// Chi è già membro "rientra" senza cambi.
    /// </summary>
    public string? Join(Guid userId, string name, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return MatchReasons.Closed;
        }

        if (IsMember(userId))
        {
            return null;
        }

        if (Phase != MatchPhases.Waiting || Drawing)
        {
            return MatchReasons.Started;
        }

        if (!_invited.Contains(userId))
        {
            return MatchReasons.NotInvited;
        }

        if (_members.Count >= MaxMembers)
        {
            return MatchReasons.Full;
        }

        _members.Add(new Member(userId, name));
        LastActivityAt = now;
        Rev++;
        return null;
    }

    /// <summary>
    /// Esce un membro che non ha aperto la sala: i suoi voti si tolgono e i
    /// match si ricalcolano su chi resta (spec P §6.3). false se non c'era o
    /// se è chi l'ha aperta: per lui si chiude la sala (<see cref="Close"/>).
    /// </summary>
    public bool Remove(Guid userId)
    {
        if (userId == CreatorId || _members.RemoveAll(m => m.UserId == userId) == 0)
        {
            return false;
        }

        _votes.Remove(userId);
        UpdateMatches();
        Rev++;
        return true;
    }

    /// <summary>"Inizia": i filtri e la prima pila (anche vuota).</summary>
    public void Start(MatchFilters filters, IReadOnlyList<Guid> stack, DateTimeOffset now)
    {
        Filters = filters;
        Phase = MatchPhases.Voting;
        Add(stack);
        LastActivityAt = now;
        Rev++;
    }

    /// <summary>"Altri 30": titoli nuovi in fondo alla pila; false se non ce n'era nessuno nuovo.</summary>
    public bool AddToStack(IReadOnlyList<Guid> more, DateTimeOffset now)
    {
        LastActivityAt = now;
        if (!Add(more))
        {
            return false;
        }

        Rev++;
        return true;
    }

    /// <summary>
    /// Il voto di un membro per il suo prossimo titolo; restituisce il motivo
    /// del no (MatchReasons) o null. I voti vanno in ordine: un altro titolo
    /// è NotNext.
    /// </summary>
    public string? Vote(Guid userId, Guid itemId, bool yes, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return MatchReasons.Closed;
        }

        if (!IsMember(userId))
        {
            return MatchReasons.NotMember;
        }

        if (Phase != MatchPhases.Voting)
        {
            return MatchReasons.NotStarted;
        }

        var next = Voted(userId);
        if (next >= _stack.Count || _stack[next] != itemId)
        {
            return MatchReasons.NotNext;
        }

        if (!_votes.TryGetValue(userId, out var mine))
        {
            mine = [];
            _votes[userId] = mine;
        }

        mine[itemId] = yes;
        LastActivityAt = now;
        UpdateMatches();
        Rev++;
        return null;
    }

    /// <summary>Chiude la sala; una sala già chiusa non cambia.</summary>
    public void Close(string reason, Guid? partyGroupId, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return;
        }

        Phase = MatchPhases.Closed;
        ClosedReason = reason;
        PartyGroupId = partyGroupId;
        ClosedAt = now;
        Drawing = false;
        Rev++;
    }

    /// <summary>
    /// Segna da quando ogni membro è senza sessioni WonderFlix (online sono gli
    /// utenti che ne hanno almeno una) e restituisce chi lo è da almeno grace
    /// (spec P §6.1). Chi torna online riparte da capo.
    /// </summary>
    public IReadOnlyList<Guid> Absent(IReadOnlySet<Guid> online, DateTimeOffset now, TimeSpan grace)
    {
        var absent = new List<Guid>();
        foreach (var member in _members)
        {
            if (online.Contains(member.UserId))
            {
                member.MissingSince = null;
                continue;
            }

            member.MissingSince ??= now;
            if (now - member.MissingSince.Value >= grace)
            {
                absent.Add(member.UserId);
            }
        }

        return absent;
    }

    /// <summary>Lo stato per le app: conteggi, pila, match e quasi match; mai i voti dei singoli.</summary>
    public MatchStateDto Snapshot() =>
        new(
            N(Id),
            Rev,
            Phase,
            N(CreatorId),
            CreatorName,
            _members.Select(m => new MatchMemberDto(N(m.UserId), m.Name, Voted(m.UserId))).ToList(),
            _stack.Select(N).ToList(),
            _matches.Select(N).ToList(),
            NearMatches(),
            ClosedReason,
            PartyGroupId is { } party ? N(party) : null);

    private int Voted(Guid userId) => _votes.TryGetValue(userId, out var mine) ? mine.Count : 0;

    private bool? VoteOf(Guid userId, Guid itemId) =>
        _votes.TryGetValue(userId, out var mine) && mine.TryGetValue(itemId, out var yes) ? yes : null;

    private bool Add(IReadOnlyList<Guid> items)
    {
        var added = false;
        foreach (var item in items)
        {
            if (_shown.Add(item))
            {
                _stack.Add(item);
                added = true;
            }
        }

        return added;
    }

    // I match crescono soltanto: i voti non cambiano e, senza un membro (e i
    // suoi no), un titolo può solo diventare match. Restano nell'ordine in cui
    // sono usciti; quelli nati insieme nell'ordine della pila.
    private void UpdateMatches()
    {
        foreach (var item in _stack)
        {
            if (!_matches.Contains(item) && _members.All(m => VoteOf(m.UserId, item) == true))
            {
                _matches.Add(item);
            }
        }
    }

    // Spec P §6.3: solo a fine pila; almeno ceil(membri / 2) sì, dal più
    // votato e, a parità, nell'ordine della pila.
    private List<MatchNearMatchDto> NearMatches()
    {
        if (!AllFinished)
        {
            return [];
        }

        var of = _members.Count;
        var threshold = (of + 1) / 2;
        return _stack
            .Where(item => !_matches.Contains(item))
            .Select((item, index) => (Item: item, Index: index, Yes: _members.Count(m => VoteOf(m.UserId, item) == true)))
            .Where(near => near.Yes >= threshold)
            .OrderByDescending(near => near.Yes)
            .ThenBy(near => near.Index)
            .Take(MaxNearMatches)
            .Select(near => new MatchNearMatchDto(N(near.Item), near.Yes, of))
            .ToList();
    }

    private static string N(Guid id) => id.ToString("N");

    private sealed class Member(Guid userId, string name)
    {
        public Guid UserId { get; } = userId;

        public string Name { get; } = name;

        /// <summary>Da quando non ha sessioni WonderFlix; null se ne ha.</summary>
        public DateTimeOffset? MissingSince { get; set; }
    }
}
