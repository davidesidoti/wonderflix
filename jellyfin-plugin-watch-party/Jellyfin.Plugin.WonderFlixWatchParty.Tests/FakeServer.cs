using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Server finto: sessioni, gruppi SyncPlay e invii, in memoria.</summary>
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender, IUserDirectory, ILibraryAccess, ILibraryTitles, INewTitlesSettings
{
    public List<CallerSession> Sessions { get; } = [];

    /// <summary>Gruppo → nomi utente dei partecipanti.</summary>
    public Dictionary<Guid, List<string>> Groups { get; } = [];

    public List<(string SessionId, string Payload)> Sent { get; } = [];

    /// <summary>Il token ricevuto a ogni invio riuscito, nello stesso ordine di <see cref="Sent"/>.</summary>
    public List<CancellationToken> SentTokens { get; } = [];

    /// <summary>Sessioni per cui l'invio lancia un errore.</summary>
    public HashSet<string> Failing { get; } = [];

    /// <summary>Utenti di Jellyfin, per id.</summary>
    public Dictionary<Guid, UserRef> Users { get; } = [];

    public CallerSession AddSession(string sessionId, string userName)
    {
        var session = new CallerSession(sessionId, Guid.NewGuid(), userName);
        Sessions.Add(session);
        return session;
    }

    public UserRef AddUser(string name, bool enabled = true, bool canJoinParties = true)
    {
        var user = new UserRef(Guid.NewGuid(), name, enabled, canJoinParties);
        Users[user.Id] = user;
        return user;
    }

    /// <summary>Una sessione WonderFlix aperta di un utente di <see cref="Users"/>.</summary>
    public CallerSession AddSession(string sessionId, UserRef user)
    {
        var session = new CallerSession(sessionId, user.Id, user.Name);
        Sessions.Add(session);
        return session;
    }

    /// <summary>I payload mandati a una sessione, in ordine.</summary>
    public IReadOnlyList<string> SentTo(string sessionId) =>
        Sent.Where(s => s.SessionId == sessionId).Select(s => s.Payload).ToList();

    // Nei test tutte le sessioni sono di WonderFlix.
    public IReadOnlyList<CallerSession> GetAppSessions() => Sessions;

    public IReadOnlyList<UserRef> GetUsers() => Users.Values.ToList();

    public UserRef? GetUser(Guid userId) => Users.GetValueOrDefault(userId);

    // Nei test il dispositivo di una sessione ha lo stesso id della sessione.
    public CallerSession? FindCaller(string? deviceId, string? client, Guid userId) =>
        Sessions.FirstOrDefault(s => s.SessionId == deviceId && s.UserId == userId);

    public bool Exists(string sessionId) => Sessions.Any(s => s.SessionId == sessionId);

    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        GetGroup(sessionId, groupId)?.Participants;

    /// <summary>Nome di ogni gruppo; di default "Host · Titolo".</summary>
    public Dictionary<Guid, string> GroupNames { get; } = [];

    /// <summary>Stato di ogni gruppo (nomi di GroupStateType); di default "Idle", come un gruppo senza coda.</summary>
    public Dictionary<Guid, string> GroupStates { get; } = [];

    /// <summary>
    /// Gruppi che una sessione non vede, come in Jellyfin quando l'utente
    /// non può vedere la coda (es. niente accesso alla libreria).
    /// </summary>
    public HashSet<(string SessionId, Guid GroupId)> Hidden { get; } = [];

    public IReadOnlyList<GroupSummary> ListGroups(string sessionId) =>
        Exists(sessionId) ? Groups.Keys.Where(id => !Hidden.Contains((sessionId, id))).Select(Summary).ToList() : [];

    public GroupSummary? GetGroup(string sessionId, Guid groupId) =>
        Exists(sessionId) && Groups.ContainsKey(groupId) && !Hidden.Contains((sessionId, groupId)) ? Summary(groupId) : null;

    private GroupSummary Summary(Guid groupId) =>
        new(
            groupId,
            GroupNames.GetValueOrDefault(groupId, "Host · Titolo"),
            GroupStates.GetValueOrDefault(groupId, "Idle"),
            Groups[groupId]);

    /// <summary>Elemento in riproduzione per sessione (spec G §6.5).</summary>
    public Dictionary<string, PlayingItem> Playing { get; } = [];

    /// <summary>Coppie (utente, elemento) che l'utente non può vedere (librerie o limiti d'età).</summary>
    public HashSet<(Guid UserId, Guid ItemId)> Unseen { get; } = [];

    /// <summary>Se true, la libreria lancia, come un errore di Jellyfin.</summary>
    public bool LibraryFails { get; set; }

    public PlayingItem? NowPlaying(string sessionId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : Exists(sessionId) ? Playing.GetValueOrDefault(sessionId) : null;

    /// <summary>Ogni CanSee, in ordine: utente ed elemento.</summary>
    public List<(Guid UserId, Guid ItemId)> SeenChecks { get; } = [];

    public bool CanSee(Guid userId, Guid itemId)
    {
        SeenChecks.Add((userId, itemId));
        return LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
            : Users.ContainsKey(userId) && !Unseen.Contains((userId, itemId));
    }

    /// <summary>Utenti con limiti sui contenuti (classificazione, tag, elementi senza classificazione).</summary>
    public HashSet<Guid> Restricted { get; } = [];

    public bool HasContentLimits(Guid userId) => !Users.ContainsKey(userId) || Restricted.Contains(userId);

    /// <summary>Titoli della libreria per id, come li rilegge il raccoglitore dei nuovi titoli.</summary>
    public Dictionary<Guid, LibraryTitle> Titles { get; } = [];

    /// <summary>Coppie (utente, serie) seguite.</summary>
    public HashSet<(Guid UserId, Guid SeriesId)> Following { get; } = [];

    /// <summary>Jellyfin sta scansionando la libreria.</summary>
    public bool ScanRunning { get; set; }

    private bool _notifyNewTitles = true;

    /// <summary>Se true, leggere la casella "Notify new titles" lancia.</summary>
    public bool SettingsFail { get; set; }

    /// <summary>La casella "Notify new titles".</summary>
    public bool NotifyNewTitles
    {
        get => SettingsFail ? throw new InvalidOperationException("configurazione non disponibile") : _notifyNewTitles;
        set => _notifyNewTitles = value;
    }

    public bool IsScanRunning => ScanRunning;

    /// <summary>Chiamato a ogni Get con l'id, prima della risposta (es. per cambiare lo stato a metà chiusura).</summary>
    public Action<Guid>? OnGet { get; set; }

    public LibraryTitle? Get(Guid itemId)
    {
        OnGet?.Invoke(itemId);
        return LibraryFails ? throw new InvalidOperationException("libreria non disponibile") : Titles.GetValueOrDefault(itemId);
    }

    /// <summary>Chiamato a ogni FollowsSeries, prima della risposta (es. per lanciare un errore).</summary>
    public Action? OnFollowsSeries { get; set; }

    /// <summary>Ogni FollowsSeries: utente, serie e se la serie ha altri episodi.</summary>
    public List<(Guid UserId, Guid SeriesId, bool HasOtherEpisodes)> FollowChecks { get; } = [];

    /// <summary>Chiavi delle serie senza altri episodi oltre a quelli nuovi (appena arrivate).</summary>
    public HashSet<string> BrandNewSeries { get; } = [];

    /// <summary>Ogni HasOtherEpisodes: la chiave della serie.</summary>
    public List<string> OtherEpisodesChecks { get; } = [];

    public bool HasOtherEpisodes(string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes)
    {
        OtherEpisodesChecks.Add(seriesKey);
        return !BrandNewSeries.Contains(seriesKey);
    }

    public bool FollowsSeries(
        Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes, bool hasOtherEpisodes)
    {
        OnFollowsSeries?.Invoke();
        FollowChecks.Add((userId, seriesId, hasOtherEpisodes));
        return Following.Contains((userId, seriesId));
    }

    public Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken)
    {
        if (Failing.Contains(sessionId))
        {
            throw new InvalidOperationException("invio fallito");
        }

        if (!Exists(sessionId))
        {
            return Task.FromResult(false);
        }

        Sent.Add((sessionId, payload));
        SentTokens.Add(cancellationToken);
        return Task.FromResult(true);
    }
}
