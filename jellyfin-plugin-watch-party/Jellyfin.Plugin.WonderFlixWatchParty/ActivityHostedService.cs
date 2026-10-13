using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// L'attività degli amici in background (spec O §6.3–6.4): all'avvio legge
/// activity.json; a inizio e fine di ogni riproduzione WonderFlix gli amici
/// rileggono "Sta guardando"; i resoconti registrano le visioni; ogni
/// <see cref="CleanupInterval"/> pulisce il registro.
/// </summary>
public sealed class ActivityHostedService(
    ISessionManager sessionManager,
    ActivityService activity,
    TimeProvider time,
    ILogger<ActivityHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si pulisce il registro (come i consigli).</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            activity.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Attività degli amici non caricata all'avvio");
        }

        sessionManager.PlaybackStart += OnPlaybackStart;
        sessionManager.PlaybackProgress += OnPlaybackProgress;
        sessionManager.PlaybackStopped += OnPlaybackStopped;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.PlaybackStart -= OnPlaybackStart;
        sessionManager.PlaybackProgress -= OnPlaybackProgress;
        sessionManager.PlaybackStopped -= OnPlaybackStopped;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private void OnPlaybackStart(object? sender, PlaybackProgressEventArgs e) =>
        Handle(e, report => activity.PlaybackChanged(report.UserId));

    // Arriva dentro la richiesta dell'app, senza try/catch di Jellyfin
    // (piano 21a, decisione 3): un errore qui farebbe fallire il resoconto.
    private void OnPlaybackProgress(object? sender, PlaybackProgressEventArgs e) =>
        Handle(e, report => activity.Report(report, stopped: false));

    private void OnPlaybackStopped(object? sender, PlaybackStopEventArgs e) =>
        Handle(e, report =>
        {
            activity.Report(report, stopped: true);
            activity.PlaybackChanged(report.UserId);
        });

    private void Handle(PlaybackProgressEventArgs e, Action<PlaybackReport> action)
    {
        try
        {
            if (PlayingTitles.Report(e) is { } report)
            {
                action(report);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Resoconto di riproduzione non gestito");
        }
    }

    private void Cleanup()
    {
        try
        {
            var removed = activity.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolte {Count} voci dell'attività degli amici", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dell'attività degli amici non riuscita");
        }
    }
}
