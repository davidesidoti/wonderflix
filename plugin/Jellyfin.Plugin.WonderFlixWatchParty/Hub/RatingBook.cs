using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Il voto di un utente a un titolo: da 1 a 10, con un commento facoltativo.</summary>
public sealed record StoredRating(Guid UserId, int Score, string? Comment, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

/// <summary>
/// I voti in memoria (spec Q §6): per titolo, un voto per utente. Non è
/// sicuro tra thread: lo usa solo RatingService, sotto lock.
/// </summary>
public sealed class RatingBook
{
    private readonly Dictionary<Guid, List<StoredRating>> _items = [];

    public StoredRating? Get(Guid itemId, Guid userId) =>
        _items.TryGetValue(itemId, out var list) ? list.Find(r => r.UserId == userId) : null;

    /// <summary>I voti del titolo (copia).</summary>
    public IReadOnlyList<StoredRating> ForItem(Guid itemId) =>
        _items.TryGetValue(itemId, out var list) ? [.. list] : [];

    /// <summary>Il voto sostituisce il precedente di quell'utente e ne tiene CreatedAt.</summary>
    public StoredRating Set(Guid itemId, Guid userId, int score, string? comment, DateTimeOffset now)
    {
        if (!_items.TryGetValue(itemId, out var list))
        {
            list = [];
            _items[itemId] = list;
        }

        var index = list.FindIndex(r => r.UserId == userId);
        var rating = new StoredRating(userId, score, comment, index < 0 ? now : list[index].CreatedAt, now);
        if (index < 0)
        {
            list.Add(rating);
        }
        else
        {
            list[index] = rating;
        }

        return rating;
    }

    /// <summary>Toglie il voto; true se c'era.</summary>
    public bool Remove(Guid itemId, Guid userId)
    {
        if (!_items.TryGetValue(itemId, out var list) || list.RemoveAll(r => r.UserId == userId) == 0)
        {
            return false;
        }

        if (list.Count == 0)
        {
            _items.Remove(itemId);
        }

        return true;
    }

    /// <summary>Toglie solo il commento (admin): punteggio e UpdatedAt restano. True se c'era.</summary>
    public bool RemoveComment(Guid itemId, Guid userId)
    {
        if (!_items.TryGetValue(itemId, out var list))
        {
            return false;
        }

        var index = list.FindIndex(r => r.UserId == userId && r.Comment is not null);
        if (index < 0)
        {
            return false;
        }

        list[index] = list[index] with { Comment = null };
        return true;
    }

    /// <summary>I voti con commento e UpdatedAt prima di <paramref name="before"/> (esclusivo), dal più recente.</summary>
    public IReadOnlyList<(Guid ItemId, StoredRating Rating)> Comments(DateTimeOffset? before, int limit) =>
        _items
            .SelectMany(kv => kv.Value.Select(r => (ItemId: kv.Key, Rating: r)))
            .Where(c => c.Rating.Comment is not null && (before is null || c.Rating.UpdatedAt < before))
            .OrderByDescending(c => c.Rating.UpdatedAt)
            .Take(limit)
            .ToList();

    /// <summary>Toglie i voti di utenti o titoli che non esistono più; restituisce quanti.</summary>
    public int Prune(Func<Guid, bool> userExists, Func<Guid, bool> itemExists)
    {
        var removed = 0;
        foreach (var itemId in _items.Keys.ToList())
        {
            var list = _items[itemId];
            if (!itemExists(itemId))
            {
                removed += list.Count;
                _items.Remove(itemId);
                continue;
            }

            removed += list.RemoveAll(r => !userExists(r.UserId));
            if (list.Count == 0)
            {
                _items.Remove(itemId);
            }
        }

        return removed;
    }

    /// <summary>Legge il file; <see cref="FormatException"/> per un id rovinato, un voto fuori da 1-10 o una voce null.</summary>
    public static RatingBook FromFile(RatingFile file)
    {
        var book = new RatingBook();
        foreach (var (key, entries) in file.Items ?? [])
        {
            var itemId = ParseId(key);
            var list = new List<StoredRating>();
            foreach (var entry in entries ?? throw new FormatException("elenco null"))
            {
                if (entry is null || entry.Score is < 1 or > 10)
                {
                    throw new FormatException("voto non valido");
                }

                list.Add(new StoredRating(ParseId(entry.UserId), entry.Score, entry.Comment, entry.CreatedAt, entry.UpdatedAt));
            }

            if (list.Count > 0)
            {
                book._items[itemId] = list;
            }
        }

        return book;
    }

    /// <summary>Il file da scrivere: per titolo, i voti dal più recente.</summary>
    public RatingFile ToFile() => new()
    {
        Items = _items.ToDictionary(
            kv => kv.Key.ToString("N", CultureInfo.InvariantCulture),
            kv => kv.Value
                .OrderByDescending(r => r.UpdatedAt)
                .Select(r => (RatingFileEntry?)new RatingFileEntry
                {
                    UserId = r.UserId.ToString("N", CultureInfo.InvariantCulture),
                    Score = r.Score,
                    Comment = r.Comment,
                    CreatedAt = r.CreatedAt,
                    UpdatedAt = r.UpdatedAt,
                })
                .ToList())!,
    };

    private static Guid ParseId(string? text) =>
        Guid.TryParseExact(text, "N", out var id) ? id : throw new FormatException("id non valido");
}
