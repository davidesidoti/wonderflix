using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// La pulizia delle sale del match (spec P §6.1) ogni
/// <see cref="CleanupInterval"/>: membri senza sessioni, sale inattive,
/// sale chiuse da dimenticare.
/// </summary>
public sealed class MatchHostedService(
    MatchService matches,
    TimeProvider time,
    ILogger<MatchHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si pulisce: con 60 s di grazia un membro esce tra 60 e 90 s.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromSeconds(30);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private void Cleanup()
    {
        try
        {
            var changes = matches.Cleanup();
            if (changes > 0)
            {
                logger.LogDebug("Pulizia delle sale del match: {Count} cambi", changes);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia delle sale del match non riuscita");
        }
    }
}
