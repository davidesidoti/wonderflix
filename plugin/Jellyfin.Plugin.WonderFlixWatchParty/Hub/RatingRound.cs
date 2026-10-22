using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Una votazione di fine party (spec Q §6.2): presenti, stati e fase. I voti
/// stanno solo nell'archivio e arrivano allo <see cref="Snapshot"/>. Puro e non
/// sicuro tra thread: lo usa RatingRoundService sotto lock.
/// </summary>
public sealed class RatingRound
{
    private readonly Dictionary<Guid, string> _names = [];
    private readonly Dictionary<Guid, string> _statuses = [];
    private readonly HashSet<Guid> _present = [];

    public RatingRound(Guid groupId, Guid itemId, DateTimeOffset openedAt, TimeSpan votingTime)
    {
        GroupId = groupId;
        ItemId = itemId;
        OpenedAt = openedAt;
        EndsAt = openedAt + votingTime;
    }

    public Guid GroupId { get; }

    public Guid ItemId { get; }

    public DateTimeOffset OpenedAt { get; }

    public DateTimeOffset EndsAt { get; }

    public string Phase { get; private set; } = RatingPhases.Voting;

    public DateTimeOffset? RevealedAt { get; private set; }

    public long Rev { get; private set; }

    public IReadOnlyCollection<Guid> PresentIds => _present;

    public bool IsPresent(Guid userId) => _present.Contains(userId);

    /// <summary>Chi entra è in Waiting (o come era prima di uscire); chi esce resta ricordato ma non si vede né si aspetta.</summary>
    public void SetPresent(IReadOnlyList<UserRef> present)
    {
        var ids = present.Select(u => u.Id).ToHashSet();
        var changed = !_present.SetEquals(ids);
        foreach (var user in present)
        {
            _names[user.Id] = user.Name;
            _statuses.TryAdd(user.Id, RatingVoterStatuses.Waiting);
        }

        _present.Clear();
        _present.UnionWith(ids);
        if (changed)
        {
            Rev++;
        }
    }

    /// <summary>Ammesso in tutte e due le fasi; chi non è presente è ignorato.</summary>
    public void Vote(Guid userId) => Mark(userId, RatingVoterStatuses.Voted);

    /// <summary>False in Revealed (o se non è presente).</summary>
    public bool Skip(Guid userId) => Phase == RatingPhases.Voting && Mark(userId, RatingVoterStatuses.Skipped);

    private bool Mark(Guid userId, string status)
    {
        if (!_present.Contains(userId))
        {
            return false;
        }

        _statuses[userId] = status;
        Rev++;
        return true;
    }

    /// <summary>"allVoted" o "timeout" se in Voting è ora di scoprire (e lo fa); altrimenti null.</summary>
    public string? RevealIfDue(DateTimeOffset now)
    {
        if (Phase != RatingPhases.Voting)
        {
            return null;
        }

        string? reason = null;
        if (!_present.Any(id => _statuses[id] == RatingVoterStatuses.Waiting))
        {
            reason = "allVoted";
        }
        else if (now >= EndsAt)
        {
            reason = "timeout";
        }

        if (reason is not null)
        {
            Reveal(now);
        }

        return reason;
    }

    /// <summary>False se già Revealed.</summary>
    public bool Reveal(DateTimeOffset now)
    {
        if (Phase == RatingPhases.Revealed)
        {
            return false;
        }

        Phase = RatingPhases.Revealed;
        RevealedAt = now;
        Rev++;
        return true;
    }

    /// <summary>Lo stato visto da <paramref name="viewerId"/>: i voti degli altri solo in Revealed.</summary>
    public RatingRoundDto Snapshot(Guid viewerId, bool viewerIsCreator, IReadOnlyDictionary<Guid, StoredRating> ratings)
    {
        var revealed = Phase == RatingPhases.Revealed;
        var present = _present.OrderBy(id => _names[id], StringComparer.OrdinalIgnoreCase).ToList();
        var voters = present.Select(id => new RatingVoterDto(id.ToString("N"), _names[id], _statuses[id])).ToList();

        RatingScoreDto? mine = ratings.TryGetValue(viewerId, out var own) ? new RatingScoreDto(own.Score, own.Comment) : null;

        List<RatingResultDto>? results = null;
        double? average = null;
        if (revealed)
        {
            results = present
                .Where(id => _statuses[id] == RatingVoterStatuses.Voted && ratings.ContainsKey(id))
                .Select(id => new RatingResultDto(id.ToString("N"), _names[id], ratings[id].Score, ratings[id].Comment))
                .OrderByDescending(r => r.Score)
                .ThenBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
            average = RatingService.Average([.. results.Select(r => r.Score)]);
        }

        return new RatingRoundDto(
            GroupId.ToString("N"), ItemId.ToString("N"), Phase, Rev, EndsAt,
            viewerIsCreator && !revealed, mine, voters, results, average);
    }
}
