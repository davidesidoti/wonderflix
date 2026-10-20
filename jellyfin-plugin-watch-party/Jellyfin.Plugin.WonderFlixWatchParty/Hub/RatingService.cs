using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I voti degli amici (spec Q §6): scheda di un titolo, voto, commenti per
/// l'admin e pulizia. File con <see cref="RatingStore"/>. Sicuro tra thread.
/// </summary>
public sealed class RatingService(
    RatingStore store,
    FriendService friends,
    IUserDirectory users,
    ILibraryAccess access,
    IRatingLibrary library,
    ILibraryTitles titles,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<RatingService> logger)
{
    /// <summary>Lunghezza massima del commento, in punti di codice (spec Q §6.1).</summary>
    public const int MaxCommentLength = 200;

    /// <summary>Commenti per pagina nell'elenco admin (spec Q §6.4).</summary>
    public const int CommentsPageSize = 50;

    private const int MinScore = 1;
    private const int MaxScore = 10;

    private readonly Lock _lock = new();
    private RatingBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private RatingBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Voti in {Path}", store.FilePath);
            }

            return _book;
        }
    }

    /// <summary>Media a una cifra, mezzi in su (7,25 → 7,3); null senza voti.</summary>
    internal static double? Average(IReadOnlyCollection<int> scores) =>
        scores.Count == 0 ? null : (double)Math.Round((decimal)scores.Sum() / scores.Count, 1, MidpointRounding.AwayFromZero);

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Book;
        }
    }

    /// <summary>
    /// La scheda del titolo per chi chiama (spec Q §6.1). Invalid se il titolo
    /// non è un film o una stagione che chi chiama vede, o se la libreria lancia.
    /// </summary>
    public HubResult<ItemRatingsDto> ForItem(Guid userId, string? itemId)
    {
        if (RatableTitle(userId, itemId) is not { } title)
        {
            return HubResult<ItemRatingsDto>.Fail(HubStatus.Invalid);
        }

        IReadOnlyList<StoredRating> all;
        lock (_lock)
        {
            all = Book.ForItem(title.Id);
        }

        var mine = all.FirstOrDefault(r => r.UserId == userId);
        var friendRatings = all
            .Where(r => r.UserId != userId && friends.AreFriends(userId, r.UserId))
            .Select(r => (Rating: r, User: users.GetUser(r.UserId)))
            .Where(x => x.User is { Enabled: true })
            .OrderByDescending(x => x.Rating.UpdatedAt)
            .Select(x => new FriendRatingDto(Id(x.Rating.UserId), x.User!.Name, x.Rating.Score, x.Rating.Comment, x.Rating.UpdatedAt))
            .ToList();
        var canRate = mine is not null || Watched(userId, title);
        return HubResult<ItemRatingsDto>.Ok(new ItemRatingsDto(
            canRate,
            mine is null ? null : new RatingScoreDto(mine.Score, mine.Comment),
            Average([.. friendRatings.Select(f => f.Score)]),
            friendRatings.Count,
            friendRatings));
    }

    /// <summary>PUT Ratings: Invalid per titolo, voto o commento non validi, o se chi chiama non ha visto il titolo né l'aveva già votato.</summary>
    public HubStatus Rate(Guid userId, string? itemId, RateRequest? request)
    {
        if (request is null || RatableTitle(userId, itemId) is not { } title)
        {
            return HubStatus.Invalid;
        }

        bool hasVote;
        lock (_lock)
        {
            hasVote = Book.Get(title.Id, userId) is not null;
        }

        return !hasVote && !Watched(userId, title)
            ? HubStatus.Invalid
            : Save(userId, title.Id, request.Score, request.Comment);
    }

    /// <summary>
    /// Scrive il voto (spec Q §6.3): valida voto e commento, conta il limite.
    /// Nessun controllo sul titolo: li fa chi chiama.
    /// </summary>
    public HubStatus Save(Guid userId, Guid itemId, int? score, string? comment)
    {
        var clean = RecommendationService.CleanMessage(comment);
        if (score is not (>= MinScore and <= MaxScore) || (clean?.EnumerateRunes().Count() ?? 0) > MaxCommentLength)
        {
            return HubStatus.Invalid;
        }

        if (!limiter.TryAcquire(Id(userId), LimitTypes.Ratings))
        {
            return HubStatus.RateLimited;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            Book.Set(itemId, userId, score.Value, clean, now);
            Persist();
        }

        return HubStatus.Ok;
    }

    /// <summary>DELETE Ratings: 204 anche senza voto; un id non valido non conta nel limite.</summary>
    public HubStatus Delete(Guid userId, string? itemId)
    {
        if (!Guid.TryParse(itemId, out var id) || id == Guid.Empty)
        {
            return HubStatus.Ok;
        }

        if (!limiter.TryAcquire(Id(userId), LimitTypes.Ratings))
        {
            return HubStatus.RateLimited;
        }

        lock (_lock)
        {
            if (Book.Remove(id, userId))
            {
                Persist();
            }
        }

        return HubStatus.Ok;
    }

    /// <summary>I voti degli utenti dati sul titolo, per utente (chi non ha votato manca).</summary>
    public IReadOnlyDictionary<Guid, StoredRating> Of(Guid itemId, IReadOnlyCollection<Guid> userIds)
    {
        lock (_lock)
        {
            return Book.ForItem(itemId).Where(r => userIds.Contains(r.UserId)).ToDictionary(r => r.UserId);
        }
    }

    /// <summary>Una pagina di commenti per l'admin, dal più recente (spec Q §6.4). Invalid se <paramref name="before"/> non è una data ISO.</summary>
    public HubResult<AdminCommentsDto> Comments(string? before)
    {
        DateTimeOffset? limit = null;
        if (before is not null)
        {
            if (!DateTimeOffset.TryParse(before, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed))
            {
                return HubResult<AdminCommentsDto>.Fail(HubStatus.Invalid);
            }

            limit = parsed;
        }

        IReadOnlyList<(Guid ItemId, StoredRating Rating)> page;
        lock (_lock)
        {
            page = Book.Comments(limit, CommentsPageSize + 1);
        }

        var shown = page.Take(CommentsPageSize).ToList();
        var items = shown
            .Select(c => new AdminCommentDto(
                Id(c.Rating.UserId),
                users.GetUser(c.Rating.UserId)?.Name ?? string.Empty,
                Id(c.ItemId),
                TitleOf(c.ItemId),
                c.Rating.Score,
                c.Rating.Comment!,
                c.Rating.UpdatedAt))
            .ToList();
        DateTimeOffset? next = page.Count > CommentsPageSize ? shown[^1].Rating.UpdatedAt : null;
        return HubResult<AdminCommentsDto>.Ok(new AdminCommentsDto(items, next));
    }

    /// <summary>Toglie il commento di un voto (spec Q §6.4); Invalid per un id non valido. Il voto resta.</summary>
    public HubStatus DeleteComment(Guid adminId, string? userId, string? itemId)
    {
        if (!Guid.TryParse(userId, out var user) || user == Guid.Empty
            || !Guid.TryParse(itemId, out var item) || item == Guid.Empty)
        {
            return HubStatus.Invalid;
        }

        bool removed;
        lock (_lock)
        {
            removed = Book.RemoveComment(item, user);
            if (removed)
            {
                Persist();
            }
        }

        if (removed)
        {
            logger.LogInformation(
                "Commento di {UserId} su {ItemId} tolto dall'admin {AdminId}", Id(user), Id(item), AdminCaller.Describe(adminId));
        }

        return HubStatus.Ok;
    }

    /// <summary>
    /// Toglie i voti di utenti spariti e di titoli che Jellyfin non ha più
    /// (spec Q §6.5); restituisce quanti. Durante una scansione o con la
    /// libreria in errore i titoli non si toccano.
    /// </summary>
    public int Cleanup()
    {
        var warned = false;
        bool ItemExists(Guid id)
        {
            if (titles.IsScanRunning)
            {
                return true;
            }

            try
            {
                return library.FindRated(id) is not null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                if (!warned)
                {
                    warned = true;
                    logger.LogWarning(ex, "Pulizia dei voti: la libreria non risponde, i titoli restano");
                }

                return true;
            }
        }

        lock (_lock)
        {
            var removed = Book.Prune(id => users.GetUser(id) is not null, ItemExists);
            if (removed > 0)
            {
                Persist();
                logger.LogDebug("Pulizia dei voti: {Count} tolti", removed);
            }

            return removed;
        }
    }

    // Il film o la stagione, se chi chiama lo vede; null anche se la libreria lancia.
    private RatedTitle? RatableTitle(Guid userId, string? itemId)
    {
        if (!Guid.TryParse(itemId, out var id) || id == Guid.Empty)
        {
            return null;
        }

        try
        {
            return library.FindRated(id) is { } title && access.CanSee(userId, id) ? title : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voti: la libreria non risponde per {ItemId}", Id(id));
            return null;
        }
    }

    private bool Watched(Guid userId, RatedTitle title)
    {
        try
        {
            return library.HasWatched(userId, title);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voti: visione non verificabile per {ItemId}", Id(title.Id));
            return false;
        }
    }

    private string TitleOf(Guid itemId)
    {
        try
        {
            return library.FindRated(itemId)?.DisplayTitle ?? string.Empty;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voti: titolo non leggibile per {ItemId}", Id(itemId));
            return string.Empty;
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
            logger.LogWarning(ex, "Voti non salvati in {Path}", store.FilePath);
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
