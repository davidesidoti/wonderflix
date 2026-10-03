using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Amici e richieste (spec F §6.2–6.3): regole di <see cref="FriendGraph"/>,
/// file di <see cref="FriendStore"/>, nomi e sessioni da Jellyfin, avvisi
/// sul WebSocket. Sicuro tra thread.
/// </summary>
public sealed class FriendService(
    FriendStore store,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<FriendService> logger)
{
    /// <summary>Lettere minime di una ricerca (spec F §6.2).</summary>
    public const int MinSearchLength = 2;

    /// <summary>Risultati al massimo di una ricerca (spec F §6.2).</summary>
    public const int MaxSearchResults = 10;

    private readonly Lock _lock = new();
    private FriendGraph? _graph;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private FriendGraph Graph
    {
        get
        {
            if (_graph is null)
            {
                _graph = store.Load();
                logger.LogInformation("Amici in {Path}", store.FilePath);
            }

            return _graph;
        }
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Graph;
        }
    }

    public FriendsResponse GetFriends(Guid userId)
    {
        var online = OnlineUsers();
        lock (_lock)
        {
            var graph = Graph;
            var friends = graph.FriendsOf(userId)
                .Select(id => users.GetUser(id))
                .OfType<UserRef>()
                .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                .Select(u => new FriendEntry(Id(u.Id), u.Name, online.Contains(u.Id), null))
                .ToList();
            return new FriendsResponse(
                friends,
                People(graph.IncomingOf(userId).Select(r => r.From)),
                People(graph.OutgoingOf(userId).Select(r => r.To)));
        }
    }

    public HubResult<IReadOnlyList<UserSearchResult>> Search(Guid userId, string? query)
    {
        var text = query?.Trim() ?? string.Empty;
        if (text.Length < MinSearchLength)
        {
            return HubResult<IReadOnlyList<UserSearchResult>>.Ok([]);
        }

        if (!limiter.TryAcquire(Id(userId), LimitTypes.Searches))
        {
            return HubResult<IReadOnlyList<UserSearchResult>>.Fail(HubStatus.RateLimited);
        }

        lock (_lock)
        {
            var graph = Graph;

            // Chi non può usare i watch party non ha gli endpoint degli amici (policy SyncPlayHasAccess): non si cerca.
            IReadOnlyList<UserSearchResult> results = users.GetUsers()
                .Where(u => u.Enabled && u.CanJoinParties && u.Id != userId
                    && u.Name.Contains(text, StringComparison.OrdinalIgnoreCase))
                .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                .Take(MaxSearchResults)
                .Select(u => new UserSearchResult(Id(u.Id), u.Name, RelationOf(graph, userId, u.Id)))
                .ToList();
            return HubResult<IReadOnlyList<UserSearchResult>>.Ok(results);
        }
    }

    /// <summary>from chiede l'amicizia a to.</summary>
    public async Task<HubStatus> RequestAsync(Guid from, Guid to)
    {
        if (!limiter.TryAcquire(Id(from), LimitTypes.FriendRequests))
        {
            return HubStatus.RateLimited;
        }

        // Senza accesso ai watch party l'altro non può rispondere (policy SyncPlayHasAccess): la richiesta resterebbe in sospeso per sempre.
        if (users.GetUser(to) is not { Enabled: true, CanJoinParties: true })
        {
            logger.LogDebug("Richiesta di amicizia {From} → {To}: utente non disponibile", from, to);
            return HubStatus.Conflict;
        }

        FriendRequestOutcome outcome;
        lock (_lock)
        {
            outcome = Graph.Request(from, to, time.GetUtcNow());
            if (outcome != FriendRequestOutcome.Rejected)
            {
                Persist();
            }
        }

        logger.LogDebug("Richiesta di amicizia {From} → {To}: {Outcome}", from, to, outcome);

        switch (outcome)
        {
            case FriendRequestOutcome.Sent:
                var name = users.GetUser(from)?.Name ?? string.Empty;
                await NotifyAsync(to, SocialEvent.FriendRequest(Id(from), name)).ConfigureAwait(false);
                return HubStatus.Ok;
            case FriendRequestOutcome.BecameFriends:
                await NotifyChangedAsync(from, to).ConfigureAwait(false);
                return HubStatus.Ok;
            default:
                return HubStatus.Conflict;
        }
    }

    /// <summary>user accetta la richiesta di from.</summary>
    public async Task<HubStatus> AcceptAsync(Guid user, Guid from)
    {
        FriendChange change;
        lock (_lock)
        {
            change = Graph.Accept(user, from);
            if (change == FriendChange.Done)
            {
                Persist();
            }
        }

        logger.LogDebug("Accettazione di {User} per la richiesta di {From}: {Change}", user, from, change);
        switch (change)
        {
            case FriendChange.Done:
                await NotifyChangedAsync(user, from).ConfigureAwait(false);
                return HubStatus.Ok;
            case FriendChange.Missing:
                return HubStatus.Forbidden;
            default:
                return HubStatus.Conflict;
        }
    }

    /// <summary>user rifiuta la richiesta di from: a from sparisce e basta.</summary>
    public Task<HubStatus> DeclineAsync(Guid user, Guid from) =>
        ChangeAsync("Rifiuto", user, from, graph => graph.Decline(user, from), missing: HubStatus.Forbidden);

    /// <summary>user annulla la propria richiesta a to.</summary>
    public Task<HubStatus> CancelAsync(Guid user, Guid to) =>
        ChangeAsync("Annullamento", user, to, graph => graph.Cancel(user, to), missing: HubStatus.Ok);

    /// <summary>user toglie friend dagli amici, per tutti e due.</summary>
    public Task<HubStatus> RemoveAsync(Guid user, Guid friend) =>
        ChangeAsync("Rimozione", user, friend, graph => graph.Remove(user, friend), missing: HubStatus.Ok);

    /// <summary>
    /// Dice agli amici online di userId di rileggere gli amici (presenza,
    /// spec F §6.3).
    /// </summary>
    public Task NotifyFriendsAsync(Guid userId)
    {
        IReadOnlyList<Guid> friends;
        lock (_lock)
        {
            friends = Graph.FriendsOf(userId);
        }

        var online = OnlineUsers();
        return Task.WhenAll(friends.Where(online.Contains).Select(f => NotifyAsync(f, SocialEvent.FriendsChanged())));
    }

    private async Task<HubStatus> ChangeAsync(
        string operation, Guid a, Guid b, Func<FriendGraph, bool> change, HubStatus missing)
    {
        bool changed;
        lock (_lock)
        {
            changed = change(Graph);
            if (changed)
            {
                Persist();
            }
        }

        if (!changed)
        {
            return missing;
        }

        logger.LogDebug("{Operation} tra {A} e {B}: fatto", operation, a, b);
        await NotifyChangedAsync(a, b).ConfigureAwait(false);
        return HubStatus.Ok;
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        Graph.Prune(id => users.GetUser(id) is not null);
        try
        {
            store.Save(Graph);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Amici non salvati in {Path}", store.FilePath);
        }
    }

    private Task NotifyChangedAsync(Guid a, Guid b) =>
        Task.WhenAll(NotifyAsync(a, SocialEvent.FriendsChanged()), NotifyAsync(b, SocialEvent.FriendsChanged()));

    private async Task NotifyAsync(Guid userId, SocialEvent socialEvent)
    {
        var payload = JsonSerializer.Serialize(socialEvent);
        var targets = sessions.GetAppSessions().Where(s => s.UserId == userId).Select(s => s.SessionId).ToList();
        await Task.WhenAll(targets.Select(sessionId => SendAsync(sessionId, payload))).ConfigureAwait(false);
    }

    private async Task SendAsync(string sessionId, string payload)
    {
        try
        {
            // Mai il token della richiesta: l'avviso non si ferma con lei.
            await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso degli amici non inviato alla sessione {SessionId}", sessionId);
        }
    }

    private HashSet<Guid> OnlineUsers() => sessions.GetAppSessions().Select(s => s.UserId).ToHashSet();

    private List<PersonEntry> People(IEnumerable<Guid> ids) =>
        ids.Select(id => users.GetUser(id))
            .OfType<UserRef>()
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u => new PersonEntry(Id(u.Id), u.Name))
            .ToList();

    private static string RelationOf(FriendGraph graph, Guid me, Guid other) =>
        graph.AreFriends(me, other) ? FriendRelations.Friend
        : graph.HasRequest(other, me) ? FriendRelations.Incoming
        : graph.HasRequest(me, other) ? FriendRelations.Outgoing
        : FriendRelations.None;

    private static string Id(Guid id) => id.ToString("N");
}
