using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// I consigli tra amici in background (spec N, piano 20a decisione 1):
/// all'avvio legge recommendations.json e accende una volta sola la riga
/// "Consigliati per te" nella Home dell'admin già salvata; ogni
/// <see cref="CleanupInterval"/> pulisce i consigli che non valgono più.
/// </summary>
public sealed class RecommendationsHostedService(
    RecommendationService recommendations,
    IHomeLayoutStore layout,
    TimeProvider time,
    ILogger<RecommendationsHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i consigli (come le notifiche).</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            recommendations.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Consigli non caricati all'avvio");
        }

        // A parte: un errore della configurazione non ferma i consigli.
        try
        {
            if (layout.AddLaterRows())
            {
                logger.LogInformation("Home dell'admin: accese le righe nuove");
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Home dell'admin: righe nuove non accese");
        }

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
            var removed = recommendations.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolti {Count} consigli che non valgono più", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dei consigli non riuscita");
        }
    }
}
