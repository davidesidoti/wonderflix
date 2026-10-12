namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Chi ha consigliato un titolo (spec N §6.1): l'amico, il messaggio (null se nessuno) e quando.</summary>
public sealed record RecommendationSender(Guid UserId, string? Message, DateTimeOffset CreatedAt);

/// <summary>Un titolo consigliato a un utente, con i mittenti dal più recente.</summary>
public sealed record RecommendedTitle(Guid ItemId, IReadOnlyList<RecommendationSender> From)
{
    /// <summary>La "data" del titolo (spec N §6.1): il consiglio più recente.</summary>
    public DateTimeOffset LatestAt => From.Count == 0 ? DateTimeOffset.MinValue : From.Max(f => f.CreatedAt);
}

/// <summary>
/// I consigli in memoria (spec N §6.1): per destinatario, titoli con i loro
/// mittenti. Non è sicuro tra thread: lo usa solo RecommendationService,
/// sotto lock.
/// </summary>
public sealed class RecommendationBook
{
    /// <summary>Titoli al massimo per destinatario: oltre esce quello con la data più vecchia.</summary>
    public const int MaxTitles = 50;

    private readonly Dictionary<Guid, List<Title>> _users = [];

    /// <summary>I titoli dell'utente dalla data più recente, ognuno con i mittenti dal più recente (copie).</summary>
    public IReadOnlyList<RecommendedTitle> List(Guid userId) =>
        _users.TryGetValue(userId, out var titles)
            ? titles.Select(t => t.Snapshot()).OrderByDescending(t => t.LatestAt).ToList()
            : [];

    /// <summary>
    /// Il consiglio di fromUserId a toUserId: se lo stesso amico aveva già
    /// consigliato il titolo, messaggio e data si aggiornano.
    /// </summary>
    public void Add(Guid toUserId, Guid itemId, Guid fromUserId, string? message, DateTimeOffset now)
    {
        var titles = Titles(toUserId);
        var title = titles.Find(t => t.ItemId == itemId);
        if (title is null)
        {
            title = new Title(itemId);
            titles.Add(title);
        }

        title.From.RemoveAll(f => f.UserId == fromUserId);
        title.From.Add(new RecommendationSender(fromUserId, message, now));
        if (titles.Count > MaxTitles)
        {
            titles.Remove(titles.MinBy(t => t.LatestAt)!);
        }
    }

    /// <summary>Toglie il titolo all'utente ("Non mi interessa"); true se c'era.</summary>
    public bool Remove(Guid userId, Guid itemId) =>
        _users.TryGetValue(userId, out var titles) && titles.RemoveAll(t => t.ItemId == itemId) > 0;

    /// <summary>
    /// Toglie il titolo solo se il suo consiglio più recente è ancora
    /// latestAt: un consiglio arrivato dopo il controllo lo tiene (piano 20a,
    /// decisione 3).
    /// </summary>
    public bool RemoveIfLatest(Guid userId, Guid itemId, DateTimeOffset latestAt) =>
        _users.TryGetValue(userId, out var titles)
        && titles.RemoveAll(t => t.ItemId == itemId && t.LatestAt == latestAt) > 0;

    /// <summary>Toglie un mittente dal titolo; il titolo senza mittenti esce. True se c'era.</summary>
    public bool RemoveSender(Guid userId, Guid itemId, Guid fromUserId)
    {
        if (!_users.TryGetValue(userId, out var titles)
            || titles.Find(t => t.ItemId == itemId) is not { } title
            || title.From.RemoveAll(f => f.UserId == fromUserId) == 0)
        {
            return false;
        }

        if (title.From.Count == 0)
        {
            titles.Remove(title);
        }

        return true;
    }

    /// <summary>
    /// Pulizia (spec N §6.3, piano 20a decisione 2): toglie i destinatari che
    /// non esistono più, i mittenti che keepSender(destinatario, mittente)
    /// scarta e poi i titoli senza mittenti o con la data prima di cutoff.
    /// Restituisce quanti titoli ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists, Func<Guid, Guid, bool> keepSender)
    {
        var removed = 0;
        foreach (var (userId, titles) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += titles.Count;
                _users.Remove(userId);
                continue;
            }

            foreach (var title in titles)
            {
                title.From.RemoveAll(f => !keepSender(userId, f.UserId));
            }

            removed += titles.RemoveAll(t => t.From.Count == 0 || t.LatestAt < cutoff);
            if (titles.Count == 0)
            {
                _users.Remove(userId);
            }
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente, un titolo o un mittente non è valido.</summary>
    public static RecommendationBook FromFile(RecommendationFile file)
    {
        var book = new RecommendationBook();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("consigli di un utente non validi");
            }

            var titles = book.Titles(userId);
            foreach (var raw in value)
            {
                if (raw is null || !Guid.TryParse(raw.ItemId, out var itemId) || raw.From is null)
                {
                    throw new FormatException("titolo consigliato non valido");
                }

                var title = new Title(itemId);
                foreach (var sender in raw.From)
                {
                    if (sender is null || !Guid.TryParse(sender.UserId, out var fromUserId))
                    {
                        throw new FormatException("mittente non valido");
                    }

                    var message = string.IsNullOrEmpty(sender.Message) ? null : sender.Message;
                    title.From.Add(new RecommendationSender(fromUserId, message, sender.CreatedAt));
                }

                if (title.From.Count > 0)
                {
                    titles.Add(title);
                }
            }
        }

        return book;
    }

    public RecommendationFile ToFile() => new()
    {
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (List<RecommendationFileTitle?>?)pair.Value
                .Select(t => t.Snapshot())
                .OrderByDescending(t => t.LatestAt)
                .Select(t => (RecommendationFileTitle?)new RecommendationFileTitle
                {
                    ItemId = t.ItemId.ToString("N"),
                    From = t.From
                        .Select(f => (RecommendationFileSender?)new RecommendationFileSender
                        {
                            UserId = f.UserId.ToString("N"),
                            Message = f.Message,
                            CreatedAt = f.CreatedAt,
                        })
                        .ToList(),
                })
                .ToList()),
    };

    private List<Title> Titles(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var titles))
        {
            titles = [];
            _users[userId] = titles;
        }

        return titles;
    }

    private sealed class Title(Guid itemId)
    {
        public Guid ItemId { get; } = itemId;

        public List<RecommendationSender> From { get; } = [];

        public DateTimeOffset LatestAt => From.Count == 0 ? DateTimeOffset.MinValue : From.Max(f => f.CreatedAt);

        public RecommendedTitle Snapshot() => new(ItemId, From.OrderByDescending(f => f.CreatedAt).ToList());
    }
}
