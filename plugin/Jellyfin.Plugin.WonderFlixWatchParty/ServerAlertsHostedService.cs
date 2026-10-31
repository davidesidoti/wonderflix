using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Gli avvisi agli admin che vengono dal server (spec V): il riavvio richiesto, controllato la prima volta dopo
/// <see cref="FirstRun"/> e poi ogni <see cref="Interval"/>. L'avviso c'è finché il riavvio è in attesa e si toglie da
/// solo quando non lo è più; un errore finisce nel log e si riprova al giro dopo.
/// </summary>
public sealed class ServerAlertsHostedService(
    IRestartState restart,
    AdminAlerts alerts,
    TimeProvider time,
    ILogger<ServerAlertsHostedService> logger) : IHostedService, IDisposable
{
    public const string RestartKey = "restart";

    /// <summary>Il primo giro: dopo l'avvio, con Jellyfin già tranquillo.</summary>
    public static readonly TimeSpan FirstRun = TimeSpan.FromMinutes(1);

    /// <summary>Ogni quanto si guarda se serve un riavvio.</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _timer = time.CreateTimer(_ => _ = CheckAsync(), null, FirstRun, Interval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        Dispose();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _timer?.Dispose();
        _timer = null;
    }

    /// <summary>Allinea l'avviso del riavvio con lo stato del server; non lancia.</summary>
    public async Task CheckAsync()
    {
        try
        {
            var pending = restart.PendingRestart;
            await alerts.SyncAsync(
                RestartKey, pending ? [new AdminAlert(RestartKey, InboxEntryTypes.RestartPending, "Jellyfin")] : []).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Avviso del riavvio non allineato");
        }
    }
}
