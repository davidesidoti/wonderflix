namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di una richiesta di amicizia (spec F §6.2).</summary>
public enum FriendRequestOutcome
{
    /// <summary>Richiesta in sospeso.</summary>
    Sent,

    /// <summary>L'altro aveva già chiesto: ora sono amici.</summary>
    BecameFriends,

    /// <summary>Non ammessa (a sé stessi, doppia, già amici, limiti).</summary>
    Rejected,
}

/// <summary>Esito di un'accettazione.</summary>
public enum FriendChange
{
    /// <summary>Fatto.</summary>
    Done,

    /// <summary>La richiesta non c'è.</summary>
    Missing,

    /// <summary>Uno dei due ha già il massimo di amici.</summary>
    Full,
}

/// <summary>Una richiesta in sospeso.</summary>
public sealed record FriendRequestRecord(Guid From, Guid To, DateTimeOffset CreatedAt);

/// <summary>
/// Amicizie e richieste in sospeso, con le loro regole (spec F §6.2): niente
/// disco, niente Jellyfin. Non è sicuro tra thread: lo protegge
/// <see cref="FriendService"/>.
/// </summary>
public sealed class FriendGraph
{
    /// <summary>Amici al massimo per utente (spec F §6.9).</summary>
    public const int MaxFriends = 200;

    /// <summary>Richieste inviate in sospeso al massimo per utente (spec F §6.9).</summary>
    public const int MaxOutgoing = 50;

    // Coppie ordinate (il Guid minore prima): una sola voce per amicizia.
    private readonly HashSet<(Guid, Guid)> _friendships = [];
    private readonly List<FriendRequestRecord> _requests = [];

    public bool AreFriends(Guid a, Guid b) => _friendships.Contains(Pair(a, b));

    public IReadOnlyList<Guid> FriendsOf(Guid user) =>
        _friendships
            .Where(p => p.Item1 == user || p.Item2 == user)
            .Select(p => p.Item1 == user ? p.Item2 : p.Item1)
            .ToList();

    public IReadOnlyList<FriendRequestRecord> IncomingOf(Guid user) => _requests.Where(r => r.To == user).ToList();

    public IReadOnlyList<FriendRequestRecord> OutgoingOf(Guid user) => _requests.Where(r => r.From == user).ToList();

    public bool HasRequest(Guid from, Guid to) => _requests.Any(r => r.From == from && r.To == to);

    /// <summary>
    /// Richiesta di from a to. Se to aveva già chiesto a from diventano
    /// subito amici (la richiesta di to sparisce).
    /// </summary>
    public FriendRequestOutcome Request(Guid from, Guid to, DateTimeOffset now)
    {
        if (from == to || AreFriends(from, to) || HasRequest(from, to))
        {
            return FriendRequestOutcome.Rejected;
        }

        if (HasRequest(to, from))
        {
            if (!CanBefriend(from, to))
            {
                return FriendRequestOutcome.Rejected;
            }

            RemoveRequest(to, from);
            _friendships.Add(Pair(from, to));
            return FriendRequestOutcome.BecameFriends;
        }

        if (OutgoingOf(from).Count >= MaxOutgoing || FriendsOf(from).Count >= MaxFriends)
        {
            return FriendRequestOutcome.Rejected;
        }

        _requests.Add(new FriendRequestRecord(from, to, now));
        return FriendRequestOutcome.Sent;
    }

    /// <summary>user accetta la richiesta di from.</summary>
    public FriendChange Accept(Guid user, Guid from)
    {
        if (!HasRequest(from, user))
        {
            return FriendChange.Missing;
        }

        if (!CanBefriend(user, from))
        {
            return FriendChange.Full;
        }

        RemoveRequest(from, user);
        _friendships.Add(Pair(user, from));
        return FriendChange.Done;
    }

    /// <summary>user rifiuta la richiesta di from; false se non c'era.</summary>
    public bool Decline(Guid user, Guid from) => RemoveRequest(from, user);

    /// <summary>user annulla la propria richiesta a to; false se non c'era.</summary>
    public bool Cancel(Guid user, Guid to) => RemoveRequest(user, to);

    /// <summary>Toglie l'amicizia per tutti e due; false se non c'era.</summary>
    public bool Remove(Guid user, Guid friend) => _friendships.Remove(Pair(user, friend));

    /// <summary>
    /// Toglie amicizie e richieste di utenti che non esistono più; true se
    /// ha tolto qualcosa.
    /// </summary>
    public bool Prune(Func<Guid, bool> exists)
    {
        var removed = _friendships.RemoveWhere(p => !exists(p.Item1) || !exists(p.Item2));
        removed += _requests.RemoveAll(r => !exists(r.From) || !exists(r.To));
        return removed > 0;
    }

    public FriendFile ToFile() => new()
    {
        Friendships = _friendships.Select(p => new[] { p.Item1.ToString("N"), p.Item2.ToString("N") }).ToList(),
        Requests = _requests
            .Select(r => new FriendFileRequest { From = r.From.ToString("N"), To = r.To.ToString("N"), CreatedAt = r.CreatedAt })
            .ToList(),
    };

    /// <summary>Lancia <see cref="FormatException"/> se il file non ha la forma attesa.</summary>
    public static FriendGraph FromFile(FriendFile file)
    {
        var graph = new FriendGraph();
        foreach (var pair in file.Friendships ?? [])
        {
            if (pair is not { Length: 2 })
            {
                throw new FormatException("amicizia senza due id");
            }

            graph._friendships.Add(Pair(ParseId(pair[0]), ParseId(pair[1])));
        }

        foreach (var request in file.Requests ?? [])
        {
            graph._requests.Add(new FriendRequestRecord(ParseId(request.From), ParseId(request.To), request.CreatedAt));
        }

        return graph;
    }

    private bool CanBefriend(Guid a, Guid b) => FriendsOf(a).Count < MaxFriends && FriendsOf(b).Count < MaxFriends;

    private bool RemoveRequest(Guid from, Guid to) => _requests.RemoveAll(r => r.From == from && r.To == to) > 0;

    private static (Guid, Guid) Pair(Guid a, Guid b) => a.CompareTo(b) <= 0 ? (a, b) : (b, a);

    private static Guid ParseId(string? value) =>
        Guid.TryParse(value, out var id) ? id : throw new FormatException("id utente non valido");
}
