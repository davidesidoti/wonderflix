namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Una visione registrata (spec O §6.4): il film o la serie, e l'ultima volta.</summary>
public sealed record WatchedTitle(Guid ItemId, DateTimeOffset WatchedAt);

/// <summary>
/// L'attività in memoria (spec O §6.1 e §6.4): chi non mostra cosa guarda
/// e le visioni di ognuno. Non è sicuro tra thread: lo usa solo
/// ActivityService, sotto lock.
/// </summary>
public sealed class ActivityBook
{
    /// <summary>Titoli al massimo per utente: oltre esce quello visto meno di recente.</summary>
    public const int MaxTitles = 100;

    private readonly HashSet<Guid> _hidden = [];
    private readonly Dictionary<Guid, List<WatchedTitle>> _users = [];

    /// <summary>L'utente mostra agli amici cosa guarda (acceso se non l'ha mai cambiato).</summary>
    public bool Shares(Guid userId) => !_hidden.Contains(userId);

    /// <summary>
    /// Cambia la scelta; spenta, toglie anche le visioni dell'utente. True se
    /// qualcosa è cambiato.
    /// </summary>
    public bool SetShare(Guid userId, bool share)
    {
        if (share)
        {
            return _hidden.Remove(userId);
        }

        var removed = _users.Remove(userId);
        return _hidden.Add(userId) || removed;
    }

    /// <summary>
    /// La visione del titolo: se c'era già si aggiorna la data. Niente (false)
    /// se l'utente non mostra cosa guarda.
    /// </summary>
    public bool Record(Guid userId, Guid itemId, DateTimeOffset at)
    {
        if (!Shares(userId))
        {
            return false;
        }

        if (!_users.TryGetValue(userId, out var titles))
        {
            titles = [];
            _users[userId] = titles;
        }

        titles.RemoveAll(t => t.ItemId == itemId);
        titles.Add(new WatchedTitle(itemId, at));
        if (titles.Count > MaxTitles)
        {
            titles.Remove(titles.MinBy(t => t.WatchedAt)!);
        }

        return true;
    }

    /// <summary>Le visioni dell'utente, dalla più recente.</summary>
    public IReadOnlyList<WatchedTitle> Views(Guid userId) =>
        _users.TryGetValue(userId, out var titles) ? titles.OrderByDescending(t => t.WatchedAt).ToList() : [];

    /// <summary>
    /// Pulizia (spec O §6.4): toglie le visioni prima di cutoff e gli utenti
    /// che non esistono più, scelte comprese. Restituisce quante voci ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists)
    {
        var removed = _hidden.RemoveWhere(id => !userExists(id));
        foreach (var (userId, titles) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += titles.Count;
                _users.Remove(userId);
                continue;
            }

            removed += titles.RemoveAll(t => t.WatchedAt < cutoff);
            if (titles.Count == 0)
            {
                _users.Remove(userId);
            }
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente o una visione non è valida.</summary>
    public static ActivityBook FromFile(ActivityFile file)
    {
        var book = new ActivityBook();
        foreach (var raw in file.Hidden ?? [])
        {
            if (!Guid.TryParse(raw, out var userId))
            {
                throw new FormatException("scelta di un utente non valida");
            }

            book._hidden.Add(userId);
        }

        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("visioni di un utente non valide");
            }

            foreach (var view in value)
            {
                if (view is null || !Guid.TryParse(view.ItemId, out var itemId))
                {
                    throw new FormatException("visione non valida");
                }

                // Chi ha spento non ha visioni, anche se il file ne avesse.
                book.Record(userId, itemId, view.WatchedAt);
            }
        }

        return book;
    }

    public ActivityFile ToFile() => new()
    {
        Hidden = _hidden.Select(id => (string?)id.ToString("N")).ToList(),
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (List<ActivityFileView?>?)pair.Value
                .OrderByDescending(t => t.WatchedAt)
                .Select(t => (ActivityFileView?)new ActivityFileView { ItemId = t.ItemId.ToString("N"), WatchedAt = t.WatchedAt })
                .ToList()),
    };
}
