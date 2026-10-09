using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// La cassetta delle notifiche (spec G §6): voci su disco con
/// <see cref="InboxStore"/>, letture e cancellazioni, annunci dell'admin,
/// voci d'invito, voci dei nuovi titoli, i promemoria dei contatti (spec L),
/// pulizia e avviso InboxChanged alle sessioni WonderFlix dell'utente.
/// Sicuro tra thread.
/// </summary>
public sealed class InboxService(
    InboxStore store,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    ILibraryAccess library,
    TimeProvider time,
    ILogger<InboxService> logger)
{
    /// <summary>Quanto resta una voce (spec G §6.1).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    /// <summary>Lunghezza massima di un annuncio, in punti di codice (spec G §6.7).</summary>
    public const int MaxAnnouncementLength = 500;

    private readonly Lock _lock = new();
    private InboxBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private InboxBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Cassetta delle notifiche in {Path}", store.FilePath);
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

    /// <summary>Le voci dell'utente dalla più recente e quante non lette.</summary>
    public InboxResponse Get(Guid userId)
    {
        lock (_lock)
        {
            var entries = Book.List(userId);
            return new InboxResponse(entries, entries.Count(e => !e.Read));
        }
    }

    /// <summary>Segna lette le voci fino a upTo.</summary>
    public Task MarkReadAsync(Guid userId, long upTo) =>
        ChangeAsync(userId, book => book.MarkRead(userId, upTo));

    /// <summary>Toglie una voce; niente se non c'è (si può ripetere).</summary>
    public Task RemoveAsync(Guid userId, string? entryId) =>
        string.IsNullOrWhiteSpace(entryId)
            ? Task.CompletedTask
            : ChangeAsync(userId, book => book.Remove(userId, entryId));

    public Task ClearAsync(Guid userId) => ChangeAsync(userId, book => book.Clear(userId));

    /// <summary>
    /// Un annuncio dell'admin a ogni utente attivo (spec G §6.7). Invalid se
    /// il testo, senza spazi ai bordi, è vuoto o più lungo di
    /// <see cref="MaxAnnouncementLength"/>.
    /// </summary>
    public async Task<HubResult<AnnouncementResponse>> AnnounceAsync(string? text)
    {
        var trimmed = text?.Trim() ?? string.Empty;
        var length = trimmed.EnumerateRunes().Count();
        if (length == 0 || length > MaxAnnouncementLength)
        {
            return HubResult<AnnouncementResponse>.Fail(HubStatus.Invalid);
        }

        var recipients = users.GetUsers().Where(u => u.Enabled).Select(u => u.Id).ToList();
        var now = time.GetUtcNow();
        lock (_lock)
        {
            foreach (var userId in recipients)
            {
                Book.Add(userId, new InboxEntry { Type = InboxEntryTypes.Announcement, CreatedAt = now, Text = trimmed });
            }

            Persist();
        }

        logger.LogDebug("Annuncio a {Count} utenti", recipients.Count);
        await NotifyAsync(recipients).ConfigureAwait(false);
        return HubResult<AnnouncementResponse>.Ok(new AnnouncementResponse(recipients.Count));
    }

    /// <summary>
    /// Le voci d'invito (spec G §6.5), solo per gli invitati attivi che
    /// possono vedere l'elemento in riproduzione nel party: quello della prima
    /// delle partySessions (le sessioni WonderFlix nel canale del party, con
    /// chi invita davanti) che sta riproducendo qualcosa. Mai l'elemento di
    /// una sessione fuori dal party; se nessuna sessione del party sta
    /// riproducendo, nessuna voce. Non lancia: un errore finisce nel log.
    /// </summary>
    public async Task AddInvitesAsync(
        string inviterName, GroupSummary group, IReadOnlyList<string> partySessions, IReadOnlyList<Guid> invitees)
    {
        if (invitees.Count == 0)
        {
            return;
        }

        try
        {
            var playing = FindPlaying(partySessions);
            if (playing is null)
            {
                logger.LogDebug("Inviti al watch party {GroupId}: niente in riproduzione, nessuna voce", group.Id);
                return;
            }

            var allowed = invitees
                .Where(userId => users.GetUser(userId) is { Enabled: true } && library.CanSee(userId, playing.ItemId))
                .ToList();
            var groupId = group.Id.ToString("N");
            var title = PartyNames.TitleOf(group.Name);
            var image = playing.ImageItemId.ToString("N");
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in allowed)
                {
                    Book.UpsertInvite(userId, groupId, inviterName, title, image, now);
                }

                if (allowed.Count > 0)
                {
                    Persist();
                }
            }

            logger.LogDebug("Voci d'invito al watch party {GroupId}: {Count}", group.Id, allowed.Count);
            await NotifyAsync(allowed).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci d'invito al watch party {GroupId} non create o non notificate", group.Id);
        }
    }

    /// <summary>
    /// Le voci dei nuovi titoli (spec G §6.6), una per utente, e l'avviso alle
    /// sue sessioni. Non lancia: un errore finisce nel log.
    /// </summary>
    public async Task AddNewTitlesAsync(IReadOnlyDictionary<Guid, InboxEntry> entries)
    {
        if (entries.Count == 0)
        {
            return;
        }

        try
        {
            lock (_lock)
            {
                foreach (var (userId, entry) in entries)
                {
                    Book.Add(userId, entry);
                }

                Persist();
            }

            await NotifyAsync(entries.Keys.ToList()).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci dei nuovi titoli non create o non notificate");
        }
    }

    /// <summary>"Ora disponibile" a chi ha chiesto il titolo (spec I §7.5). Non lancia.</summary>
    public Task AddRequestAvailableAsync(Guid userId, RequestEvent request) =>
        AddRequestAsync(InboxEntryTypes.RequestAvailable, [userId], request, requesterName: null);

    /// <summary>"Nuova richiesta" a chi può approvare (spec I §7.5). Non lancia.</summary>
    public Task AddRequestPendingAsync(IReadOnlyList<Guid> userIds, RequestEvent request, string requesterName) =>
        AddRequestAsync(InboxEntryTypes.RequestPending, userIds, request, requesterName);

    /// <summary>
    /// Il promemoria "Proteggi il tuo account" (spec L §7.7): sostituisce
    /// quello di prima, quindi ce n'è sempre uno solo. Non lancia: un errore
    /// finisce nel log. Restituisce true quando la voce è nella cassetta (anche
    /// se l'avviso alle sessioni non è partito), false se non è stata scritta.
    /// </summary>
    public async Task<bool> AddContactReminderAsync(Guid userId, IReadOnlyList<string> channels)
    {
        var written = false;
        try
        {
            var now = time.GetUtcNow();
            lock (_lock)
            {
                Book.RemoveType(userId, InboxEntryTypes.ContactReminder);
                Book.Add(userId, new InboxEntry
                {
                    Type = InboxEntryTypes.ContactReminder,
                    CreatedAt = now,
                    Channels = channels.ToList(),
                });
                Persist();
            }

            written = true;
            await NotifyAsync([userId]).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non creato per {UserId}", userId.ToString("N"));
        }

        return written;
    }

    /// <summary>Toglie i promemoria dei contatti (un contatto è stato verificato). Non lancia.</summary>
    public async Task RemoveContactRemindersAsync(Guid userId)
    {
        try
        {
            await ChangeAsync(userId, book => book.RemoveType(userId, InboxEntryTypes.ContactReminder)).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non tolti per {UserId}", userId.ToString("N"));
        }
    }

    private async Task AddRequestAsync(
        string type, IReadOnlyList<Guid> userIds, RequestEvent request, string? requesterName)
    {
        if (userIds.Count == 0)
        {
            return;
        }

        try
        {
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in userIds)
                {
                    Book.UpsertRequest(userId, new InboxEntry
                    {
                        Type = type,
                        CreatedAt = now,
                        RequestId = request.RequestId,
                        MediaType = request.MediaType,
                        TmdbId = request.TmdbId,
                        Title = request.Title,
                        Seasons = request.Seasons?.ToList(),
                        ItemId = type == InboxEntryTypes.RequestAvailable ? request.ItemId : null,
                        RequesterName = requesterName,
                    });
                }

                Persist();
            }

            logger.LogDebug(
                "Voce {Type} della richiesta {RequestId} a {Count} utenti", type, request.RequestId, userIds.Count);
            await NotifyAsync(userIds).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci della richiesta {RequestId} non create o non notificate", request.RequestId);
        }
    }

    /// <summary>
    /// Toglie le voci più vecchie di <see cref="MaxAge"/> e le cassette degli
    /// utenti cancellati da Jellyfin; restituisce quante voci.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            var removed = Book.Prune(time.GetUtcNow() - MaxAge, userId => users.GetUser(userId) is not null);
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    private PlayingItem? FindPlaying(IReadOnlyList<string> partySessions)
    {
        foreach (var sessionId in partySessions)
        {
            var playing = library.NowPlaying(sessionId);
            if (playing is not null)
            {
                return playing;
            }
        }

        return null;
    }

    private async Task ChangeAsync(Guid userId, Func<InboxBook, bool> change)
    {
        bool changed;
        lock (_lock)
        {
            changed = change(Book);
            if (changed)
            {
                Persist();
            }
        }

        if (changed)
        {
            await NotifyAsync([userId]).ConfigureAwait(false);
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
            logger.LogWarning(ex, "Cassetta delle notifiche non salvata in {Path}", store.FilePath);
        }
    }

    private Task NotifyAsync(IReadOnlyCollection<Guid> userIds)
    {
        var payload = JsonSerializer.Serialize(SocialEvent.InboxChanged());
        var targets = sessions.GetAppSessions()
            .Where(s => userIds.Contains(s.UserId))
            .Select(s => s.SessionId)
            .ToList();
        return Task.WhenAll(targets.Select(sessionId => SendAsync(sessionId, payload)));
    }

    private async Task SendAsync(string sessionId, string payload)
    {
        try
        {
            // Mai il token della richiesta: l'avviso non si ferma con lei.
            await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso della cassetta non inviato alla sessione {SessionId}", sessionId);
        }
    }
}
