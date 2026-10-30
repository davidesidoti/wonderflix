using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// I timer dello spazio (spec U §6.3, §7.3): il calcolo dopo <see cref="FirstScanDelay"/> e poi ogni
/// <see cref="ScanInterval"/>, il controllo dei torrent in attesa ogni <see cref="SpaceService.PendingInterval"/> e la
/// coda delle operazioni per tutta la vita del servizio. Un calcolo alla volta lo garantisce il servizio.
/// </summary>
public sealed class SpaceHostedService(
    SpaceService space,
    TimeProvider time,
    ILogger<SpaceHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Il primo calcolo dopo l'avvio, a Radarr, Sonarr e qBittorrent il tempo di essere pronti.</summary>
    public static readonly TimeSpan FirstScanDelay = TimeSpan.FromMinutes(2);

    /// <summary>Un calcolo al giorno.</summary>
    public static readonly TimeSpan ScanInterval = TimeSpan.FromHours(24);

    private readonly CancellationTokenSource _stop = new();
    private ITimer? _scanTimer;
    private ITimer? _pendingTimer;
    private Task _operations = Task.CompletedTask;
    private int _pendingRunning;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            space.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Spazio non caricato all'avvio");
        }

        _scanTimer = time.CreateTimer(_ => _ = ScanAsync(), null, FirstScanDelay, ScanInterval);
        _pendingTimer = time.CreateTimer(_ => _ = CheckPendingAsync(), null, SpaceService.PendingInterval, SpaceService.PendingInterval);
        _operations = RunOperationsAsync();
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        Dispose();
        try
        {
            await _operations.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
    }

    public void Dispose()
    {
        _stop.Cancel();
        _scanTimer?.Dispose();
        _pendingTimer?.Dispose();
        _scanTimer = _pendingTimer = null;
    }

    private async Task ScanAsync()
    {
        try
        {
            await space.ScanAsync(_stop.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            // Solo il tipo: il messaggio potrebbe contenere un percorso.
            logger.LogWarning("Spazio: calcolo non riuscito ({Error})", ex.GetType().Name);
        }
    }

    private async Task RunOperationsAsync()
    {
        try
        {
            await space.RunOperationsAsync(_stop.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            // Solo il tipo: il messaggio potrebbe contenere un percorso.
            logger.LogError("Spazio: la coda delle operazioni si è fermata ({Error})", ex.GetType().Name);
        }
    }

    // Un controllo alla volta: un tick che ne trova uno in corso salta.
    private async Task CheckPendingAsync()
    {
        if (Interlocked.CompareExchange(ref _pendingRunning, 1, 0) != 0)
        {
            return;
        }

        try
        {
            await space.CheckPendingAsync(_stop.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            logger.LogWarning("Spazio: controllo dei torrent in attesa non riuscito ({Error})", ex.GetType().Name);
        }
        finally
        {
            Volatile.Write(ref _pendingRunning, 0);
        }
    }
}
