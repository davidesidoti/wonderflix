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
    IUserDirectory users,
    ISessionDirectory sessions,
    PresenceTracker presence,
    TimeProvider time,
    ILogger<ActivityService> logger)
{
    /// <summary>Posizione da cui una riproduzione conta come visione (spec O §6.4).</summary>
    public static readonly TimeSpan MinWatch = TimeSpan.FromMinutes(5);

    /// <summary>Quanto resta una visione nel registro e nella riga (spec O §6.4, §6.6).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

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
        var watched = report.Completed || report.PositionTicks >= MinWatch.Ticks;
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

    private static string Id(Guid id) => id.ToString("N");
}
