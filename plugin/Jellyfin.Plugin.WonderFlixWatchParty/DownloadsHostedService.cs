using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// I timer dei download automatici (spec T §5, §6, decisione 7): carica il file all'avvio, un giro ogni
/// <see cref="DownloadService.CycleInterval"/>, l'elenco da ripassare ogni <see cref="DownloadService.ReviewInterval"/>
/// (il primo dopo <see cref="FirstReviewDelay"/>). Un giro alla volta: un tick che ne trova uno in corso salta; un
/// nudge che ne trova uno in corso lo fa ripartire una volta dopo <see cref="DownloadService.NudgeDelay"/>.
/// </summary>
public sealed class DownloadsHostedService(
    DownloadService downloads,
    TimeProvider time,
    ILogger<DownloadsHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Il primo "da ripassare" dopo l'avvio, a Radarr e Sonarr il tempo di essere pronti.</summary>
    public static readonly TimeSpan FirstReviewDelay = TimeSpan.FromMinutes(5);

    private readonly CancellationTokenSource _stop = new();
    private ITimer? _cycleTimer;
    private ITimer? _reviewTimer;
    private ITimer? _nudgeTimer;
    private int _cycleRunning;
    private int _reviewRunning;
    private int _nudgeScheduled;
    private int _rerun;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            downloads.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Download automatici non caricati all'avvio");
        }

        _cycleTimer = time.CreateTimer(_ => _ = CycleAsync(nudged: false), null, DownloadService.CycleInterval, DownloadService.CycleInterval);
        _reviewTimer = time.CreateTimer(_ => _ = ReviewAsync(), null, FirstReviewDelay, DownloadService.ReviewInterval);
        _nudgeTimer = time.CreateTimer(_ => OnNudgeTimer(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);

        // Per ultimo: un nudge prima che i timer esistano lascerebbe _nudgeScheduled a 1 per sempre.
        downloads.Nudged += ScheduleNudge;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        Dispose();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        downloads.Nudged -= ScheduleNudge;
        _stop.Cancel();
        _cycleTimer?.Dispose();
        _reviewTimer?.Dispose();
        _nudgeTimer?.Dispose();
        _cycleTimer = _reviewTimer = _nudgeTimer = null;
    }

    // Più nudge vicini fanno un giro solo: il timer a colpo singolo si arma una volta.
    private void ScheduleNudge()
    {
        // Durante lo spegnimento un'approvazione non deve fallire: il nudge si perde e basta.
        if (_stop.IsCancellationRequested)
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _nudgeScheduled, 1, 0) == 0)
        {
            try
            {
                _nudgeTimer?.Change(DownloadService.NudgeDelay, Timeout.InfiniteTimeSpan);
            }
            catch (ObjectDisposedException)
            {
            }
        }
    }

    private void OnNudgeTimer()
    {
        Volatile.Write(ref _nudgeScheduled, 0);
        _ = CycleAsync(nudged: true);
    }

    // Un giro alla volta. Un nudge che lo trova in corso lascia "rifai": il giro, finito, ne arma un altro.
    // Il flag si scrive prima del tentativo, così un nudge non si perde tra la fine del giro e il suo controllo.
    private async Task CycleAsync(bool nudged)
    {
        if (nudged)
        {
            Volatile.Write(ref _rerun, 1);
        }

        if (Interlocked.CompareExchange(ref _cycleRunning, 1, 0) != 0)
        {
            return;
        }

        Volatile.Write(ref _rerun, 0);
        try
        {
            await downloads.RunCycleAsync(_stop.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Giro dei download automatici non riuscito");
        }
        finally
        {
            // Exchange (barriera piena): il rilascio non deve passare dopo la lettura di _rerun.
            Interlocked.Exchange(ref _cycleRunning, 0);
            if (Volatile.Read(ref _rerun) == 1 && !_stop.IsCancellationRequested)
            {
                ScheduleNudge();
            }
        }
    }

    // L'elenco da ripassare ha la sua guardia: legge soltanto e non deve girare due volte insieme.
    private async Task ReviewAsync()
    {
        if (Interlocked.CompareExchange(ref _reviewRunning, 1, 0) != 0)
        {
            return;
        }

        try
        {
            await downloads.BuildReviewAsync(_stop.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Elenco da ripassare dei download automatici non riuscito");
        }
        finally
        {
            Volatile.Write(ref _reviewRunning, 0);
        }
    }
}
