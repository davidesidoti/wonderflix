using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Toglie dai gruppi le sessioni finite, avvisa gli amici quando una
/// sessione WonderFlix si apre o si chiude (spec F §6.3) e, ogni
/// <see cref="CleanupInterval"/>, pulisce registro e storico dei gruppi
/// finiti (spec E §6.5). Alla stessa pulizia toglie le notifiche scadute
/// (spec G §6.1).
/// </summary>
public sealed class WatchPartyHostedService(
    ISessionManager sessionManager,
    PartyHub hub,
    FriendService friends,
    PresenceTracker presence,
    PartyService parties,
    InboxService inbox,
    TimeProvider time,
    ILogger<WatchPartyHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i gruppi finiti.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionStarted += OnSessionStarted;
        sessionManager.SessionEnded += OnSessionEnded;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        logger.LogInformation("WonderFlix Watch Party {Version} avviato", typeof(Plugin).Assembly.GetName().Version);
        try
        {
            friends.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Amici non caricati all'avvio");
        }

        try
        {
            inbox.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Cassetta delle notifiche non caricata all'avvio");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionStarted -= OnSessionStarted;
        sessionManager.SessionEnded -= OnSessionEnded;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    // Gli eventi arrivano su un altro thread e poi la SessionInfo viene
    // chiusa: si legge subito quello che serve.
    private void OnSessionStarted(object? sender, SessionEventArgs e) =>
        PresenceChanged(e.SessionInfo.Client, e.SessionInfo.UserId);

    private void OnSessionEnded(object? sender, SessionEventArgs e)
    {
        var session = e.SessionInfo;
        var (id, client, userId) = (session.Id, session.Client, session.UserId);
        hub.RemoveSession(id);
        PresenceChanged(client, userId);
    }

    private void PresenceChanged(string? client, Guid userId)
    {
        if (string.Equals(client, WatchPartyProtocol.ClientName, StringComparison.Ordinal) && !userId.Equals(Guid.Empty))
        {
            presence.Changed(userId);
        }
    }

    private void Cleanup()
    {
        try
        {
            var removed = hub.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolti {Count} watch party finiti", removed);
            }

            var removedParties = parties.Cleanup();
            if (removedParties > 0)
            {
                logger.LogDebug("Tolti {Count} party finiti", removedParties);
            }

            var removedEntries = inbox.Cleanup();
            if (removedEntries > 0)
            {
                logger.LogDebug("Tolte {Count} notifiche scadute", removedEntries);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dei watch party non riuscita");
        }
    }
}
