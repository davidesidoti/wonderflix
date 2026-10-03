using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Le cassette delle notifiche in memoria (spec G §6.1–6.2, §6.5): voci,
/// Seq, letture, limiti, inviti che si aggiornano. Non è sicuro tra
/// thread: lo usa solo InboxService, sotto lock.
/// </summary>
public sealed class InboxBook
{
    /// <summary>Voci al massimo per utente: oltre si toglie quella con il Seq più basso.</summary>
    public const int MaxEntries = 100;

    private readonly Dictionary<Guid, UserInbox> _users = [];

    /// <summary>Le voci dell'utente dalla più recente (Seq più alto), come copie.</summary>
    public IReadOnlyList<InboxEntry> List(Guid userId) =>
        _users.TryGetValue(userId, out var inbox)
            ? inbox.Entries.OrderByDescending(e => e.Seq).Select(e => e.Copy()).ToList()
            : [];

    /// <summary>Aggiunge una voce, che prende il Seq (e un Id se non l'ha); restituisce una copia.</summary>
    public InboxEntry Add(Guid userId, InboxEntry entry)
    {
        var inbox = Inbox(userId);
        if (string.IsNullOrEmpty(entry.Id))
        {
            entry.Id = Guid.NewGuid().ToString("N");
        }

        entry.Seq = inbox.NextSeq++;
        inbox.Entries.Add(entry);
        if (inbox.Entries.Count > MaxEntries)
        {
            inbox.Entries.Remove(inbox.Entries.MinBy(e => e.Seq)!);
        }

        return entry.Copy();
    }

    /// <summary>
    /// L'invito al gruppo (spec G §6.5): se l'utente ne ha già uno per lo
    /// stesso gruppo lo aggiorna (mittente, ora, di nuovo non letto, Seq
    /// nuovo: torna in cima), altrimenti lo aggiunge. Restituisce una copia.
    /// </summary>
    public InboxEntry UpsertInvite(
        Guid userId, string groupId, string fromName, string title, string imageItemId, DateTimeOffset now)
    {
        var inbox = Inbox(userId);
        var existing = inbox.Entries.FirstOrDefault(e =>
            e.Type == InboxEntryTypes.Invite && string.Equals(e.GroupId, groupId, StringComparison.OrdinalIgnoreCase));
        if (existing is null)
        {
            return Add(userId, new InboxEntry
            {
                Type = InboxEntryTypes.Invite,
                CreatedAt = now,
                GroupId = groupId,
                FromName = fromName,
                Title = title,
                ImageItemId = imageItemId,
            });
        }

        existing.FromName = fromName;
        existing.Title = title;
        existing.ImageItemId = imageItemId;
        existing.CreatedAt = now;
        existing.Read = false;
        existing.Seq = inbox.NextSeq++;
        return existing.Copy();
    }

    /// <summary>Segna lette le voci con Seq fino a upTo; true se qualcosa è cambiato.</summary>
    public bool MarkRead(Guid userId, long upTo)
    {
        if (!_users.TryGetValue(userId, out var inbox))
        {
            return false;
        }

        var changed = false;
        foreach (var entry in inbox.Entries.Where(e => !e.Read && e.Seq <= upTo))
        {
            entry.Read = true;
            changed = true;
        }

        return changed;
    }

    /// <summary>Toglie una voce; true se c'era.</summary>
    public bool Remove(Guid userId, string entryId) =>
        _users.TryGetValue(userId, out var inbox)
        && inbox.Entries.RemoveAll(e => string.Equals(e.Id, entryId, StringComparison.OrdinalIgnoreCase)) > 0;

    /// <summary>Svuota la cassetta (il Seq continua da dov'era); true se c'era qualcosa.</summary>
    public bool Clear(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var inbox) || inbox.Entries.Count == 0)
        {
            return false;
        }

        inbox.Entries.Clear();
        return true;
    }

    /// <summary>
    /// Toglie le voci create prima di cutoff e le cassette degli utenti che
    /// non esistono più; restituisce quante voci ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists)
    {
        var removed = 0;
        foreach (var (userId, inbox) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += inbox.Entries.Count;
                _users.Remove(userId);
                continue;
            }

            removed += inbox.Entries.RemoveAll(e => e.CreatedAt < cutoff);
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente o una voce non è valida.</summary>
    public static InboxBook FromFile(InboxFile file)
    {
        var book = new InboxBook();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("cassetta di un utente non valida");
            }

            var inbox = book.Inbox(userId);
            foreach (var entry in value.Entries ?? [])
            {
                if (entry is null || string.IsNullOrEmpty(entry.Id) || string.IsNullOrEmpty(entry.Type))
                {
                    throw new FormatException("voce non valida");
                }

                inbox.Entries.Add(entry);
            }

            // Un NextSeq scritto a mano non deve ridare un Seq già usato.
            inbox.NextSeq = Math.Max(value.NextSeq, inbox.Entries.Select(e => e.Seq).DefaultIfEmpty(0).Max() + 1);
        }

        return book;
    }

    public InboxFile ToFile() => new()
    {
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (InboxFileUser?)new InboxFileUser
            {
                NextSeq = pair.Value.NextSeq,
                Entries = pair.Value.Entries.OrderBy(e => e.Seq).Select(e => (InboxEntry?)e.Copy()).ToList(),
            }),
    };

    private UserInbox Inbox(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var inbox))
        {
            inbox = new UserInbox();
            _users[userId] = inbox;
        }

        return inbox;
    }

    private sealed class UserInbox
    {
        public long NextSeq { get; set; } = 1;

        public List<InboxEntry> Entries { get; } = [];
    }
}
