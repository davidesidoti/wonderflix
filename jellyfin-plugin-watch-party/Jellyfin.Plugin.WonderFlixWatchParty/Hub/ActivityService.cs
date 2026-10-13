using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Cosa guardano gli amici (spec O §6): "Mostra agli amici cosa guardo",
/// registro delle visioni WonderFlix, "Sta guardando", posizione per
/// "Guarda insieme", riga "Visti dagli amici" e pulizia. File con
/// <see cref="ActivityStore"/>. Sicuro tra thread.
/// </summary>
public sealed class ActivityService(
    ActivityStore store,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    IPlaybackDirectory playback,
    PartyRegistry registry,
    ILibraryAccess access,
    IRecommendationLibrary library,
    PresenceTracker presence,
    TimeProvider time,
    ILogger<ActivityService> logger)
{
    /// <summary>Posizione da cui una riproduzione conta come visione (spec O §6.4).</summary>
    public static readonly TimeSpan MinWatch = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Età massima dell'ultimo resoconto perché uno stop conti per posizione:
    /// l'app riporta ogni 10 secondi, quindi un resoconto più vecchio vuol dire
    /// che lo stop viene dal controllo di inattività di Jellyfin, che ha fatto
    /// avanzare la posizione da sé (non guardata davvero).
    /// </summary>
    public static readonly TimeSpan MaxReportAge = TimeSpan.FromMinutes(1);

    /// <summary>Quanto resta una visione nel registro e nella riga (spec O §6.4, §6.6).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    /// <summary>Titoli al massimo nella riga "Visti dagli amici" (spec O §6.6).</summary>
    public const int MaxFriendsWatched = 30;

    /// <summary>Titoli al massimo controllati con la libreria per riempire la riga (spec O §6.6).</summary>
    public const int MaxChecked = 60;

    private readonly Lock _lock = new();

    // Solo sotto _lock: le visioni già registrate, per sessione e titolo (piano 21a, decisione 8).
    private readonly HashSet<(string SessionId, Guid TitleId)> _recorded = [];

    private ActivityBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private ActivityBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Attività degli amici in {Path}", store.FilePath);
            }

            return _book;
        }
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Book;
        }
    }

    /// <summary>L'utente mostra agli amici cosa guarda (acceso se non l'ha mai cambiato).</summary>
    public bool Shares(Guid userId)
    {
        lock (_lock)
        {
            return Book.Shares(userId);
        }
    }

    /// <summary>
    /// "Mostra agli amici cosa guardo" (spec O §6.1): spenta, le visioni
    /// dell'utente si cancellano. Se è cambiata, gli amici rileggono.
    /// </summary>
    public void SetShare(Guid userId, bool share)
    {
        bool changed;
        lock (_lock)
        {
            changed = Book.SetShare(userId, share);
            if (changed)
            {
                Persist();
            }
        }

        if (changed)
        {
            logger.LogDebug("Condivisione dell'attività di {UserId}: {Share}", userId, share);
            presence.Changed(userId);
        }
    }

    /// <summary>
    /// Una riproduzione WonderFlix è iniziata o finita (spec O §6.3): gli
    /// amici rileggono "Sta guardando", se l'utente lo mostra.
    /// </summary>
    public void PlaybackChanged(Guid userId)
    {
        if (Shares(userId))
        {
            presence.Changed(userId);
        }
    }

    /// <summary>
    /// Un resoconto vero (spec O §6.4): la visione si registra alla prima
    /// posizione oltre <see cref="MinWatch"/>, oppure allo stop se si è
    /// arrivati alla fine o oltre <see cref="MinWatch"/>; una volta per
    /// sessione e titolo (piano 21a, decisione 8).
    /// </summary>
    public void Report(PlaybackReport report, bool stopped)
    {
        var fresh = !stopped || time.GetUtcNow() - report.LastCheckIn <= MaxReportAge;
        var watched = report.Completed || (fresh && report.PositionTicks >= MinWatch.Ticks);
        lock (_lock)
        {
            var already = report.TitleId is { } id && _recorded.Contains((report.SessionId, id));
            if (stopped)
            {
                _recorded.RemoveWhere(r => r.SessionId == report.SessionId);
            }

            if (already || !watched || report.TitleId is not { } titleId)
            {
                return;
            }

            if (!stopped)
            {
                _recorded.Add((report.SessionId, titleId));
            }

            if (Book.Record(report.UserId, titleId, time.GetUtcNow()))
            {
                Persist();
                logger.LogDebug("Visione di {ItemId} registrata per {UserId}", Id(titleId), report.UserId);
            }
        }
    }

    /// <summary>
    /// Pulizia periodica (spec O §6.4): visioni oltre <see cref="MaxAge"/>,
    /// utenti che non esistono più, sessioni finite senza stop. Restituisce
    /// quante voci ha tolto dal registro.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            _recorded.RemoveWhere(r => !sessions.Exists(r.SessionId));
            var removed = Book.Prune(time.GetUtcNow() - MaxAge, userId => users.GetUser(userId) is not null);
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        try
        {
            store.Save(Book);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Attività degli amici non salvata in {Path}", store.FilePath);
        }
    }

    /// <summary>
    /// Cosa guarda friendId, se viewerId può saperlo (spec O §6.2); null
    /// altrimenti. Non controlla l'amicizia: la chiama GET Friends solo per
    /// gli amici online fuori da un party visibile.
    /// </summary>
    public FriendNowPlaying? NowPlayingFor(Guid viewerId, Guid friendId)
    {
        if (Playing(viewerId, friendId) is not { } current)
        {
            return null;
        }

        var item = current.Item;
        return new FriendNowPlaying(
            Id(item.ItemId), item.Name, item.SeriesId is { } series ? Id(series) : null, item.SeriesName, item.Season, item.Episode);
    }

    /// <summary>
    /// Dove è arrivato l'amico, per "Guarda insieme" (spec O §6.5). Conflict
    /// se non è amico, non guarda, non lo mostra o chi chiama non vede il titolo.
    /// </summary>
    public HubResult<FriendPosition> Position(Guid callerId, string? friendId)
    {
        if (!Guid.TryParse(friendId, out var id)
            || !friends.AreFriends(callerId, id)
            || Playing(callerId, id) is not { } current)
        {
            return HubResult<FriendPosition>.Fail(HubStatus.Conflict);
        }

        return HubResult<FriendPosition>.Ok(new FriendPosition(Id(current.Item.ItemId), current.PositionTicks));
    }

    /// <summary>
    /// La riga "Visti dagli amici" (spec O §6.6): le visioni degli ultimi
    /// <see cref="MaxAge"/> degli amici attivi che mostrano cosa guardano,
    /// per titolo dal più recente, senza i titoli che chi chiama non vede o
    /// ha già visto o iniziato. Un errore della libreria salta il titolo.
    /// </summary>
    public FriendsWatchedResponse FriendsWatched(Guid callerId)
    {
        var cutoff = time.GetUtcNow() - MaxAge;
        var friendUsers = friends.FriendsOf(callerId)
            .Select(users.GetUser)
            .OfType<UserRef>()
            .Where(u => u.Enabled)
            .ToList();
        List<Candidate> candidates;
        lock (_lock)
        {
            candidates = friendUsers
                .Where(u => Book.Shares(u.Id))
                .SelectMany(u => Book.Views(u.Id).Where(v => v.WatchedAt >= cutoff).Select(v => (User: u, View: v)))
                .GroupBy(x => x.View.ItemId)
                .Select(g => new Candidate(
                    g.Key,
                    g.OrderByDescending(x => x.View.WatchedAt)
                        .Select(x => new FriendWatcher(Id(x.User.Id), x.User.Name, x.View.WatchedAt))
                        .ToList()))
                .OrderByDescending(c => c.By[0].WatchedAt)
                .Take(MaxChecked)
                .ToList();
        }

        // Fuori dal lock: domande alla libreria.
        var items = new List<FriendsWatchedItem>();
        foreach (var candidate in candidates)
        {
            if (items.Count == MaxFriendsWatched)
            {
                break;
            }

            try
            {
                if (!access.CanSee(callerId, candidate.ItemId) || library.LastWatched(callerId, candidate.ItemId) is not null)
                {
                    continue;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Titolo {ItemId} saltato in Visti dagli amici", Id(candidate.ItemId));
                continue;
            }

            items.Add(new FriendsWatchedItem(Id(candidate.ItemId), candidate.By));
        }

        return new FriendsWatchedResponse(items);
    }

    // La riproduzione di friendId che viewerId può conoscere (spec O §6.2 e §6.5), o null.
    private AppPlayback? Playing(Guid viewerId, Guid friendId)
    {
        try
        {
            // Dentro il try: un file illeggibile non deve rompere GET Friends (fallisce sicuro).
            if (!Shares(friendId))
            {
                return null;
            }

            // Un party, anche nascosto a chi guarda, non si rivela con "Sta guardando" (piano 21a, decisione 6).
            if (sessions.GetAppSessions().Any(s => s.UserId == friendId && registry.GroupOf(s.SessionId) is not null))
            {
                return null;
            }

            var current = playback.GetAppPlayback().Where(p => p.UserId == friendId).MaxBy(p => p.LastCheckIn);
            return current is not null && access.CanSee(viewerId, current.Item.ItemId) ? current : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Riproduzione di {UserId} non letta", friendId);
            return null;
        }
    }

    private static string Id(Guid id) => id.ToString("N");

    private sealed record Candidate(Guid ItemId, List<FriendWatcher> By);
}
