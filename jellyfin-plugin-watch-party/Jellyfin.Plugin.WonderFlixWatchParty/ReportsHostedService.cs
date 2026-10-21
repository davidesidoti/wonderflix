using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>Carica le segnalazioni all'avvio e le tiene pulite ogni <see cref="StoreInterval"/> (spec R §6.5).</summary>
public sealed class ReportsHostedService(
    ReportService reports,
    TimeProvider time,
    ILogger<ReportsHostedService> logger) : IHostedService, IDisposable
{
    public static readonly TimeSpan StoreInterval = TimeSpan.FromMinutes(5);

    private ITimer? _storeTimer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            reports.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Segnalazioni non caricate all'avvio");
        }

        _storeTimer = time.CreateTimer(_ => Run(reports.Cleanup), null, StoreInterval, StoreInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        Dispose();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _storeTimer?.Dispose();
        _storeTimer = null;
    }

    private void Run(Func<int> cleanup)
    {
        try
        {
            var changes = cleanup();
            if (changes > 0)
            {
                logger.LogDebug("Pulizia delle segnalazioni: {Count} cambi", changes);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia delle segnalazioni non riuscita");
        }
    }
}
