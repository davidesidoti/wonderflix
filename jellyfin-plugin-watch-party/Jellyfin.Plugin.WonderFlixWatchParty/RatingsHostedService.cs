using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Carica i voti all'avvio e li tiene puliti con due timer (spec Q §6.5):
/// le votazioni ogni <see cref="RoundsInterval"/>, l'archivio ogni <see cref="StoreInterval"/>.
/// </summary>
public sealed class RatingsHostedService(
    RatingService ratings,
    RatingRoundService rounds,
    TimeProvider time,
    ILogger<RatingsHostedService> logger) : IHostedService, IDisposable
{
    public static readonly TimeSpan RoundsInterval = TimeSpan.FromSeconds(30);

    public static readonly TimeSpan StoreInterval = TimeSpan.FromMinutes(5);

    private ITimer? _roundsTimer;
    private ITimer? _storeTimer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            ratings.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Voti non caricati all'avvio");
        }

        _roundsTimer = time.CreateTimer(_ => Run("delle votazioni", rounds.Cleanup), null, RoundsInterval, RoundsInterval);
        _storeTimer = time.CreateTimer(_ => Run("dei voti", ratings.Cleanup), null, StoreInterval, StoreInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        Dispose();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _roundsTimer?.Dispose();
        _roundsTimer = null;
        _storeTimer?.Dispose();
        _storeTimer = null;
    }

    private void Run(string what, Func<int> cleanup)
    {
        try
        {
            var changes = cleanup();
            if (changes > 0)
            {
                logger.LogDebug("Pulizia {What}: {Count} cambi", what, changes);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia {What} non riuscita", what);
        }
    }
}
