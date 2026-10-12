using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I consigli tra amici (spec N §6): destinatari, invio con voce nella
/// cassetta, filtro a lettura, "Non mi interessa" e pulizia. File con
/// <see cref="RecommendationStore"/>. Sicuro tra thread.
/// </summary>
public sealed class RecommendationService(
    RecommendationStore store,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    ILibraryAccess access,
    IRecommendationLibrary library,
    InboxService inbox,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<RecommendationService> logger)
{
    /// <summary>Quanto resta un titolo dopo il suo consiglio più recente (spec N §6.3).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(60);

    /// <summary>Lunghezza massima del messaggio, in punti di codice (spec N §6.2).</summary>
    public const int MaxMessageLength = 200;

    /// <summary>Destinatari al massimo in una richiesta (spec N §6.2).</summary>
    public const int MaxRecipients = 50;

    private readonly Lock _lock = new();
    private RecommendationBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private RecommendationBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Consigli in {Path}", store.FilePath);
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

    /// <summary>
    /// Gli amici attivi di chi chiama, per nome, con online e accesso al
    /// titolo (spec N §6.2). Invalid se il titolo non è un film o una serie
    /// che chi chiama vede.
    /// </summary>
    public HubResult<RecommendationTargetsResponse> Targets(Guid callerId, string? itemId)
    {
        if (Recommendable(callerId, itemId) is not { } item)
        {
            return HubResult<RecommendationTargetsResponse>.Fail(HubStatus.Invalid);
        }

        var online = sessions.GetAppSessions().Select(s => s.UserId).ToHashSet();
        var targets = friends.FriendsOf(callerId)
            .Select(users.GetUser)
            .OfType<UserRef>()
            .Where(u => u.Enabled)
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u => new RecommendationTarget(Id(u.Id), u.Name, online.Contains(u.Id), access.CanSee(u.Id, item.Id)))
            .ToList();
        return HubResult<RecommendationTargetsResponse>.Ok(new RecommendationTargetsResponse(targets));
    }

    /// <summary>
    /// Consiglia il titolo (spec N §6.2). Invalid per titolo, messaggio o
    /// destinatari non validi; i destinatari che non vanno bene si saltano in
    /// silenzio; RateLimited oltre il limite, senza salvare niente.
    /// </summary>
    public async Task<HubResult<RecommendResponse>> RecommendAsync(Guid callerId, RecommendRequest? request)
    {
        if (request is null || Recommendable(callerId, request.ItemId) is not { } item)
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.Invalid);
        }

        var message = CleanMessage(request.Message);
        if ((message?.EnumerateRunes().Count() ?? 0) > MaxMessageLength
            || request.To is not { Count: > 0 } to
            || to.Count > MaxRecipients)
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.Invalid);
        }

        var recipients = to
            .Select(raw => Guid.TryParse(raw, out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty && id != callerId)
            .Distinct()
            .Where(id => friends.AreFriends(callerId, id)
                && users.GetUser(id) is { Enabled: true }
                && access.CanSee(id, item.Id))
            .ToList();
        if (recipients.Count == 0)
        {
            logger.LogDebug("Consiglio di {ItemId}: nessun destinatario valido", Id(item.Id));
            return HubResult<RecommendResponse>.Ok(new RecommendResponse(0));
        }

        if (!limiter.TryAcquire(Id(callerId), LimitTypes.Recommendations, recipients.Count))
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.RateLimited);
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            foreach (var userId in recipients)
            {
                Book.Add(userId, item.Id, callerId, message, now);
            }

            Persist();
        }

        logger.LogDebug("Consiglio di {ItemId} a {Count} amici", Id(item.Id), recipients.Count);
        var fromName = users.GetUser(callerId)?.Name ?? string.Empty;
        await inbox.AddRecommendationsAsync(callerId, fromName, item, message, recipients).ConfigureAwait(false);
        return HubResult<RecommendResponse>.Ok(new RecommendResponse(recipients.Count));
    }

    /// <summary>
    /// I consigli validi dell'utente (spec N §6.3), dalla data più recente.
    /// Quello che non vale più si toglie dall'archivio. Le domande alla
    /// libreria si fanno fuori dal lock (piano 20a, decisione 3); un errore
    /// della libreria tiene il titolo (decisione 4).
    /// </summary>
    public RecommendationsResponse List(Guid userId)
    {
        IReadOnlyList<RecommendedTitle> titles;
        lock (_lock)
        {
            titles = Book.List(userId);
        }

        var cutoff = time.GetUtcNow() - MaxAge;
        var keep = new List<RecommendedTitle>();
        var lostSenders = new List<(Guid ItemId, Guid FromUserId)>();
        var lostTitles = new List<RecommendedTitle>();
        foreach (var title in titles)
        {
            var from = title.From.Where(f => users.GetUser(f.UserId) is not null && friends.AreFriends(userId, f.UserId)).ToList();
            lostSenders.AddRange(title.From.Where(f => !from.Contains(f)).Select(f => (title.ItemId, f.UserId)));
            if (from.Count == 0)
            {
                continue;
            }

            var current = title with { From = from };
            if (current.LatestAt < cutoff)
            {
                lostTitles.Add(current);
                continue;
            }

            try
            {
                if (!access.CanSee(userId, title.ItemId) || library.LastWatched(userId, title.ItemId) > current.LatestAt)
                {
                    lostTitles.Add(current);
                    continue;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Consiglio di {ItemId}: libreria non disponibile, il titolo resta", Id(title.ItemId));
            }

            keep.Add(current);
        }

        if (lostSenders.Count > 0 || lostTitles.Count > 0)
        {
            lock (_lock)
            {
                var changed = false;
                foreach (var (itemId, fromUserId) in lostSenders)
                {
                    changed |= Book.RemoveSender(userId, itemId, fromUserId);
                }

                foreach (var title in lostTitles)
                {
                    changed |= Book.RemoveIfLatest(userId, title.ItemId, title.LatestAt);
                }

                if (changed)
                {
                    Persist();
                }
            }

            logger.LogDebug(
                "Consigli di {UserId}: tolti {Titles} titoli e {Senders} mittenti", Id(userId), lostTitles.Count, lostSenders.Count);
        }

        var items = keep
            .OrderByDescending(t => t.LatestAt)
            .Select(t => new RecommendationItem(
                Id(t.ItemId),
                t.From
                    .Select(f => new RecommendationFrom(Id(f.UserId), users.GetUser(f.UserId)?.Name ?? string.Empty, f.Message, f.CreatedAt))
                    .ToList()))
            .ToList();
        return new RecommendationsResponse(items);
    }

    /// <summary>"Non mi interessa" (spec N §6.2): toglie il titolo; niente se non c'è o l'id non vale.</summary>
    public void Dismiss(Guid userId, string? itemId)
    {
        if (!Guid.TryParse(itemId, out var id))
        {
            return;
        }

        lock (_lock)
        {
            if (Book.Remove(userId, id))
            {
                Persist();
            }
        }
    }

    /// <summary>
    /// Pulizia periodica (piano 20a, decisione 2): mittenti che non esistono
    /// più o non sono più amici, titoli oltre <see cref="MaxAge"/>,
    /// destinatari cancellati. Restituisce quanti titoli ha tolto.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            var removed = Book.Prune(
                time.GetUtcNow() - MaxAge,
                userId => users.GetUser(userId) is not null,
                (to, from) => users.GetUser(from) is not null && friends.AreFriends(to, from));
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    /// <summary>
    /// Gli a capo diventano spazi, le righe vuote spariscono, spazi ai bordi
    /// tolti (piano 20a, decisione 6); null se non resta niente.
    /// </summary>
    internal static string? CleanMessage(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var joined = string.Join(' ', text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        return joined.Length == 0 ? null : joined;
    }

    // Il titolo, se è un film o una serie che chi chiama vede.
    private RecommendableItem? Recommendable(Guid callerId, string? itemId) =>
        Guid.TryParse(itemId, out var id) && id != Guid.Empty
        && library.GetTitle(id) is { } item
        && access.CanSee(callerId, id)
            ? item
            : null;

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
            logger.LogWarning(ex, "Consigli non salvati in {Path}", store.FilePath);
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
