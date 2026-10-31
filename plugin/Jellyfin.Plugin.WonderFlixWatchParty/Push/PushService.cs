using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>
/// Le notifiche push (spec V): porta le voci nuove della cassetta a ogni
/// dispositivo iscritto dell'utente, dopo preferenze, stato dell'utente,
/// ruolo e accesso del dispositivo. Tiene le iscrizioni e le preferenze.
/// </summary>
public sealed class PushService(
    NotificationStore store,
    VapidKeyProvider vapid,
    IPushTransport transport,
    IDeviceAccess devices,
    IUserDirectory users,
    TimeProvider time,
    ILogger<PushService> logger)
{
    /// <summary>Il contatto VAPID: i servizi push lo vogliono, nessuno lo legge.</summary>
    public const string VapidSubject = "mailto:noreply@wonderflix.invalid";

    private const int P256dhBytes = 65;
    private const int AuthBytes = 16;

    private readonly Lock _lock = new();
    private NotificationBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private NotificationBook Book => _book ??= store.Load();

    /// <summary>Spedisce le voci in sottofondo e torna subito: un errore finisce nel log, mai nella cassetta.</summary>
    public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh)
    {
        if (fresh.Count == 0)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await DeliverAsync(fresh).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Notifiche push non spedite");
            }
        });
    }

    /// <summary>Come <see cref="Deliver"/>, ma si aspetta la fine (per i test).</summary>
    internal async Task DeliverAsync(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh)
    {
        foreach (var (userId, entry) in fresh)
        {
            if (!NotificationCatalog.Types.Contains(entry.Type))
            {
                continue;
            }

            IReadOnlyList<PushSubscription> targets;
            lock (_lock)
            {
                targets = Book.IsEnabled(userId, entry.Type) ? Book.For(userId) : [];
            }

            if (targets.Count == 0
                || users.GetUser(userId) is not { Enabled: true } user
                || (NotificationCatalog.AudienceOf(entry.Type) == NotificationAudience.Admins && !user.IsAdmin))
            {
                continue;
            }

            foreach (var sub in targets)
            {
                if (!devices.HasAccess(userId, sub.DeviceId))
                {
                    // Logout o sessione revocata: quel dispositivo non deve più ricevere niente.
                    Change(book => book.Remove(userId, sub.Endpoint));
                    logger.LogInformation("Iscrizione push a {Host} tolta: il dispositivo non ha più accesso", Host(sub));
                    continue;
                }

                if (await SendAsync(sub, entry).ConfigureAwait(false) == PushResult.Gone)
                {
                    Change(book => book.RemoveEndpoint(sub.Endpoint));
                }
            }
        }
    }

    /// <summary>GET Notifications: i tipi che chi chiama può ricevere, nell'ordine del catalogo.</summary>
    public NotificationsResponse Get(Guid userId, bool isAdmin, bool isApprover)
    {
        var publicKey = vapid.Get().PublicKey;
        lock (_lock)
        {
            return new NotificationsResponse(
                publicKey,
                NotificationCatalog.Types
                    .Where(type => Visible(type, isAdmin, isApprover))
                    .Select(type => new NotificationTypeDto(type, Book.IsEnabled(userId, type)))
                    .ToList());
        }
    }

    /// <summary>PUT Notifications/Types: false se il tipo non esiste o chi chiama non lo vede.</summary>
    public bool SetEnabled(Guid userId, string type, bool enabled, bool isAdmin, bool isApprover)
    {
        if (!NotificationCatalog.Types.Contains(type) || !Visible(type, isAdmin, isApprover))
        {
            return false;
        }

        Change(book => book.SetEnabled(userId, type, enabled));
        return true;
    }

    /// <summary>POST Notifications/Subscriptions: Invalid se l'endpoint non è https o le chiavi non sono quelle di un browser.</summary>
    public HubStatus Subscribe(Guid userId, string deviceId, SubscribeRequest? request)
    {
        if (request is null
            || !Uri.TryCreate(request.Endpoint, UriKind.Absolute, out var uri)
            || uri.Scheme != Uri.UriSchemeHttps
            || !Base64Url.TryDecode(request.P256dh ?? "", out var p256dh) || p256dh.Length != P256dhBytes
            || !Base64Url.TryDecode(request.Auth ?? "", out var auth) || auth.Length != AuthBytes)
        {
            return HubStatus.Invalid;
        }

        var subscription = new PushSubscription
        {
            UserId = userId,
            Endpoint = request.Endpoint!,
            P256dh = request.P256dh!,
            Auth = request.Auth!,
            DeviceId = deviceId,
            Language = request.Language == "it" ? "it" : "en",
            CreatedAt = time.GetUtcNow(),
        };
        Change(book =>
        {
            book.Upsert(subscription);
            return true;
        });
        return HubStatus.Ok;
    }

    /// <summary>DELETE Notifications/Subscriptions: solo l'iscrizione di chi chiama; niente se non c'è.</summary>
    public void Unsubscribe(Guid userId, string endpoint) =>
        Change(book => book.Remove(userId, endpoint));

    private static bool Visible(string type, bool isAdmin, bool isApprover) => NotificationCatalog.AudienceOf(type) switch
    {
        NotificationAudience.Everyone => true,
        NotificationAudience.Approvers => isApprover,
        _ => isAdmin,
    };

    private static string Host(PushSubscription sub) =>
        Uri.TryCreate(sub.Endpoint, UriKind.Absolute, out var uri) ? uri.Host : "?";

    // Un'iscrizione rotta (chiavi, firma, rete) non ferma le altre: nel log solo l'host e il tipo dell'errore.
    private async Task<PushResult> SendAsync(PushSubscription sub, InboxEntry entry)
    {
        try
        {
            // Il tipo è già controllato in DeliverAsync: il catalogo lo conosce.
            var message = NotificationCatalog.Message(entry, sub.Language)!;

            // Solo testo e rotta: niente chiavi, codici o percorsi (spec V §2). Il tag è la voce, così il browser non la ripete.
            var payload = JsonSerializer.SerializeToUtf8Bytes(new
            {
                title = message.Title,
                body = message.Body,
                route = message.Route,
                tag = entry.Id,
            });
            var body = WebPushCrypto.Encrypt(payload, Base64Url.Decode(sub.P256dh), Base64Url.Decode(sub.Auth));
            var authorization = VapidSigner.AuthorizationHeader(sub.Endpoint, vapid.Get(), VapidSubject, time.GetUtcNow());
            return await transport.SendAsync(sub, body, authorization, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning("Push a {Host} non riuscito: {Error}", Host(sub), ex.GetType().Name);
            return PushResult.Failed;
        }
    }

    // Cambia l'archivio sotto lock e lo salva se è cambiato qualcosa. Un errore di disco non annulla il cambio in
    // memoria: finisce nel log e si riprova alla scrittura successiva.
    private void Change(Func<NotificationBook, bool> change)
    {
        lock (_lock)
        {
            if (!change(Book))
            {
                return;
            }

            try
            {
                store.Save(Book);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                logger.LogWarning(ex, "Iscrizioni push non salvate in {Path}", store.FilePath);
            }
        }
    }
}
