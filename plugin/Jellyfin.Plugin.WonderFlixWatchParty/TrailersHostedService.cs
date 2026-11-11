using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>Svuota la cache dei trailer all'avvio, toglie i file vecchi ogni <see cref="SweepInterval"/> e allo stop annulla i download in corso.</summary>
public sealed class TrailersHostedService(TrailerCache cache, TrailerService trailers, TimeProvider time, ILogger<TrailersHostedService> logger)
    : IHostedService, IDisposable
{
    public static readonly TimeSpan SweepInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            cache.Clear();
            logger.LogInformation("Trailer: cache svuotata");
        }
        catch (Exception ex)
        {
            // Solo il tipo: il messaggio potrebbe contenere un percorso.
            logger.LogWarning("Trailer: cache non svuotata ({Error})", ex.GetType().Name);
        }

        _timer = time.CreateTimer(_ => Sweep(), null, SweepInterval, SweepInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        trailers.Stop();
        Dispose();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _timer?.Dispose();
        _timer = null;
    }

    private void Sweep()
    {
        try
        {
            cache.Sweep();
        }
        catch (Exception ex)
        {
            logger.LogWarning("Trailer: pulizia non riuscita ({Error})", ex.GetType().Name);
        }
    }
}
