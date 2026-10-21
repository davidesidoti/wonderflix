using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Server finto: sessioni, gruppi SyncPlay e invii, in memoria.</summary>
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender, IUserDirectory, ILibraryAccess, ILibraryTitles, INewTitlesSettings, IRecommendationLibrary, IPlaybackDirectory, IMatchLibrary, IRatingLibrary, IReportLibrary
{
    /// <summary>Titoli che si possono segnalare (spec R), per id.</summary>
    public Dictionary<Guid, ReportedItem> ReportedItems { get; } = [];

    /// <summary>Se true, <see cref="Find"/> lancia, come un errore di Jellyfin.</summary>
    public bool ReportLibraryFails { get; set; }

    public ReportedItem AddMovie(string name)
    {
        var id = Guid.NewGuid();
        return ReportedItems[id] = new ReportedItem(id, "Movie", name, id, name, null, null);
    }

    public (ReportedItem Series, ReportedItem Season, ReportedItem Episode) AddEpisode(string series, int season, int episode)
    {
        var seriesId = Guid.NewGuid();
        var seriesItem = ReportedItems[seriesId] = new ReportedItem(seriesId, "Series", series, seriesId, series, null, null);
        var seasonId = Guid.NewGuid();
        var seasonItem = ReportedItems[seasonId] = new ReportedItem(seasonId, "Season", $"Stagione {season}", seriesId, series, season, null);
        var episodeId = Guid.NewGuid();
        var episodeItem = ReportedItems[episodeId] = new ReportedItem(episodeId, "Episode", $"Episodio {episode}", seriesId, series, season, episode);
        return (seriesItem, seasonItem, episodeItem);
    }

    public ReportedItem? Find(Guid itemId) =>
        ReportLibraryFails ? throw new InvalidOperationException("libreria non disponibile") : ReportedItems.GetValueOrDefault(itemId);

    /// <summary>Film e stagioni che si possono votare (spec Q), per id.</summary>
    public Dictionary<Guid, RatedTitle> RatedTitles { get; } = [];

    /// <summary>Cosa si vota a fine party, per elemento in riproduzione.</summary>
    public Dictionary<Guid, Guid> RoundTargets { get; } = [];

    /// <summary>Coppie (utente, titolo) che l'utente ha visto.</summary>
    public HashSet<(Guid UserId, Guid ItemId)> WatchedTitles { get; } = [];

    /// <summary>Se true, i metodi di IRatingLibrary lanciano, come un errore di Jellyfin.</summary>
    public bool RatingLibraryFails { get; set; }

    public RatedTitle AddRated(string displayTitle, bool isSeason = false)
    {
        var title = new RatedTitle(Guid.NewGuid(), isSeason, displayTitle);
        RatedTitles[title.Id] = title;
        return title;
    }

    public RatedTitle? FindRated(Guid itemId) =>
        RatingLibraryFails ? throw new InvalidOperationException("libreria non disponibile") : RatedTitles.GetValueOrDefault(itemId);

    public Guid? RoundTarget(Guid itemId) =>
        RatingLibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : RoundTargets.TryGetValue(itemId, out var target) ? target : null;

    public bool HasWatched(Guid userId, RatedTitle title) =>
        RatingLibraryFails ? throw new InvalidOperationException("libreria non disponibile") : WatchedTitles.Contains((userId, title.Id));

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

    public UserRef AddUser(string name, bool enabled = true, bool canJoinParties = true, bool isAdmin = false, bool canManageSubtitles = false)
    {
        var user = new UserRef(Guid.NewGuid(), name, enabled, canJoinParties, isAdmin, canManageSubtitles);
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

    /// <summary>Film e serie che si possono consigliare (spec N), per id.</summary>
    public Dictionary<Guid, RecommendableItem> Recommendables { get; } = [];

    /// <summary>Ultima visione per (utente, film o serie).</summary>
    public Dictionary<(Guid UserId, Guid ItemId), DateTimeOffset> Watched { get; } = [];

    public RecommendableItem AddRecommendable(string name, int? year = null)
    {
        var item = new RecommendableItem(Guid.NewGuid(), name, year);
        Recommendables[item.Id] = item;
        return item;
    }

    public RecommendableItem? GetTitle(Guid itemId) => Recommendables.GetValueOrDefault(itemId);

    public DateTimeOffset? LastWatched(Guid userId, Guid itemId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : Watched.TryGetValue((userId, itemId), out var at) ? at : null;

    /// <summary>Le riproduzioni nelle sessioni WonderFlix (spec O).</summary>
    public List<AppPlayback> Playback { get; } = [];

    /// <summary>Se true, leggere le riproduzioni lancia, come un errore di Jellyfin.</summary>
    public bool PlaybackFails { get; set; }

    public IReadOnlyList<AppPlayback> GetAppPlayback() =>
        PlaybackFails ? throw new InvalidOperationException("sessioni non disponibili") : Playback;

    /// <summary>I candidati della query a caso del match, già "a caso" nell'ordine della lista.</summary>
    public List<MatchCandidate> MatchCandidates { get; } = [];

    /// <summary>Ogni query del match: utente, filtri, esclusi, limite.</summary>
    public List<(Guid UserId, MatchFilters Filters, IReadOnlyCollection<Guid> Exclude, int Limit)> MatchQueries { get; } = [];

    /// <summary>Se true, la query del match lancia, come un errore del database.</summary>
    public bool MatchLibraryFails { get; set; }

    /// <summary>Eseguito all'inizio di Candidates: simula qualcosa che accade durante la pescata fuori dal lock.</summary>
    public Action? OnMatchCandidates { get; set; }

    // Come Jellyfin: niente esclusi; tipo e genere li ricontrolla chi chiama.
    public IReadOnlyList<MatchCandidate> Candidates(Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit)
    {
        OnMatchCandidates?.Invoke();
        MatchQueries.Add((userId, filters, exclude.ToList(), limit));
        return MatchLibraryFails
            ? throw new InvalidOperationException("database non disponibile")
            : MatchCandidates.Where(c => !exclude.Contains(c.Id)).Take(limit).ToList();
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
