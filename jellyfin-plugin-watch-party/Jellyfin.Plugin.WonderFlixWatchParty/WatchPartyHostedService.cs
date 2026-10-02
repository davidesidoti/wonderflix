using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Toglie dai gruppi le sessioni finite e, ogni <see cref="CleanupInterval"/>,
/// registro e storico dei gruppi finiti (spec E §6.5).
/// </summary>
public sealed class WatchPartyHostedService(
    ISessionManager sessionManager,
    PartyHub hub,
    TimeProvider time,
    ILogger<WatchPartyHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i gruppi finiti.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionEnded += OnSessionEnded;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        logger.LogInformation("WonderFlix Watch Party {Version} avviato", typeof(Plugin).Assembly.GetName().Version);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionEnded -= OnSessionEnded;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    // L'evento arriva su un altro thread e poi la SessionInfo viene chiusa:
    // si legge subito l'id.
    private void OnSessionEnded(object? sender, SessionEventArgs e) => hub.RemoveSession(e.SessionInfo.Id);

    private void Cleanup()
    {
        try
        {
            var removed = hub.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolti {Count} watch party finiti", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dei watch party non riuscita");
        }
    }
}
