using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito del webhook: 401 con il segreto sbagliato, altrimenti 200.</summary>
public enum WebhookResult
{
    Accepted,
    Unauthorized,
}

/// <summary>
/// Il webhook di Seerr (spec I §7.5): controlla il segreto e trasforma
/// "disponibile" e "in attesa" in voci della cassetta. Ricorda l'ultimo
/// evento per la pagina del plugin. Un evento incompleto si scarta con una
/// riga nel registro e risponde comunque 200, così Seerr non insiste.
/// </summary>
public sealed class RequestWebhookHandler(
    ISeerrSettings settings,
    SeerrUserMap seerrUsers,
    IUserDirectory users,
    InboxService inbox,
    TimeProvider time,
    ILogger<RequestWebhookHandler> logger)
{
    /// <summary>Corpo massimo del webhook.</summary>
    public const long MaxBodyBytes = 64 * 1024;

    /// <summary>Al massimo una riga nel registro per i segreti sbagliati in questo intervallo.</summary>
    public static readonly TimeSpan RejectedLogEvery = TimeSpan.FromMinutes(1);

    public const string MediaAvailable = "MEDIA_AVAILABLE";
    public const string MediaPending = "MEDIA_PENDING";

    /// <summary>Il nome della voce di "extra" con le stagioni chieste.</summary>
    public const string RequestedSeasons = "Requested Seasons";

    private readonly Lock _lock = new();
    private DateTimeOffset? _lastEventAt;
    private string? _lastEventType;
    private DateTimeOffset _lastRejectedLog = DateTimeOffset.MinValue;

    /// <summary>Data e tipo dell'ultimo evento con il segreto giusto (pagina del plugin).</summary>
    public (DateTimeOffset? At, string? Type) LastEvent
    {
        get
        {
            lock (_lock)
            {
                return (_lastEventAt, _lastEventType);
            }
        }
    }

    public async Task<WebhookResult> HandleAsync(SeerrWebhookPayload? payload, CancellationToken cancellationToken)
    {
        var secret = settings.WebhookSecret;
        if (payload is null || string.IsNullOrEmpty(secret) || !SecretMatches(payload.Secret, secret))
        {
            LogRejected();
            return WebhookResult.Unauthorized;
        }

        lock (_lock)
        {
            _lastEventAt = time.GetUtcNow();
            _lastEventType = payload.NotificationType;
        }

        switch (payload.NotificationType)
        {
            case MediaAvailable:
                await AvailableAsync(payload).ConfigureAwait(false);
                break;
            case MediaPending:
                await PendingAsync(payload, cancellationToken).ConfigureAwait(false);
                break;
            default:
                // TEST_NOTIFICATION e gli altri tipi: solo "Ultimo evento ricevuto".
                break;
        }

        return WebhookResult.Accepted;
    }

    /// <summary>Confronto in tempo costante (a parità di lunghezza).</summary>
    internal static bool SecretMatches(string? given, string expected) =>
        given is not null
        && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(given), Encoding.UTF8.GetBytes(expected));

    /// <summary>L'evento, o null se mancano richiesta, tipo, id TMDB o titolo.</summary>
    internal static RequestEvent? Parse(SeerrWebhookPayload payload)
    {
        var mediaType = payload.MediaType switch
        {
            RequestMediaTypes.Movie => RequestMediaTypes.Movie,
            RequestMediaTypes.Tv => RequestMediaTypes.Tv,
            _ => null,
        };
        if (mediaType is null
            || !int.TryParse(payload.RequestId, NumberStyles.None, CultureInfo.InvariantCulture, out var requestId)
            || requestId <= 0
            || !int.TryParse(payload.MediaTmdbId, NumberStyles.None, CultureInfo.InvariantCulture, out var tmdbId)
            || tmdbId <= 0
            || string.IsNullOrWhiteSpace(payload.Subject))
        {
            return null;
        }

        return new RequestEvent(
            requestId,
            mediaType,
            tmdbId,
            payload.Subject.Trim(),
            mediaType == RequestMediaTypes.Tv ? ParseSeasons(payload.Extra) : null,
            SeerrMapping.JellyfinId(payload.MediaJellyfinMediaId));
    }

    /// <summary>Le stagioni da "Requested Seasons" ("1, 2"), in ordine e senza doppioni; null se nessuna.</summary>
    internal static IReadOnlyList<int>? ParseSeasons(IEnumerable<SeerrWebhookExtra>? extra)
    {
        var value = extra?.FirstOrDefault(e => e.Name == RequestedSeasons)?.Value;
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var seasons = value
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(s => int.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : 0)
            .Where(n => n > 0)
            .Distinct()
            .Order()
            .ToList();
        return seasons.Count == 0 ? null : seasons;
    }

    private async Task AvailableAsync(SeerrWebhookPayload payload)
    {
        var request = Parse(payload);
        var requester = SeerrMapping.ParseGuid(payload.RequestedByJellyfinUserId);
        if (request is null || requester is not { } userId || users.GetUser(userId) is null)
        {
            logger.LogInformation(
                "Webhook di Seerr {Type} scartato: dati mancanti o utente sconosciuto", payload.NotificationType);
            return;
        }

        await inbox.AddRequestAvailableAsync(userId, request).ConfigureAwait(false);
    }

    private async Task PendingAsync(SeerrWebhookPayload payload, CancellationToken cancellationToken)
    {
        var request = Parse(payload);
        if (request is null)
        {
            logger.LogInformation("Webhook di Seerr {Type} scartato: dati mancanti", payload.NotificationType);
            return;
        }

        IReadOnlyList<Guid> managers;
        try
        {
            managers = await seerrUsers.ManagerJellyfinIdsAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (SeerrException ex)
        {
            logger.LogWarning("Webhook di Seerr {Type}: chi approva non letto ({Error})", payload.NotificationType, ex.Error);
            return;
        }

        var requester = SeerrMapping.ParseGuid(payload.RequestedByJellyfinUserId);
        var recipients = managers
            .Where(id => id != requester && users.GetUser(id) is { Enabled: true })
            .ToList();
        await inbox.AddRequestPendingAsync(recipients, request, payload.RequestedByUsername?.Trim() ?? string.Empty)
            .ConfigureAwait(false);
    }

    private void LogRejected()
    {
        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (now - _lastRejectedLog < RejectedLogEvery)
            {
                return;
            }

            _lastRejectedLog = now;
        }

        logger.LogWarning("Webhook di Seerr rifiutato: segreto mancante o sbagliato");
    }
}
