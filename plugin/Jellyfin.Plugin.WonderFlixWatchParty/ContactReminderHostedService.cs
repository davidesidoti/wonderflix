using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Legge i contatti all'avvio e manda i promemoria (spec L §7.7): la prima
/// volta dopo <see cref="FirstRun"/>, poi ogni <see cref="Interval"/>. Un
/// errore finisce nel log e si riprova al giro dopo.
/// </summary>
public sealed class ContactReminderHostedService(
    ContactReminders reminders,
    ContactRegistry contacts,
    TimeProvider time,
    ILogger<ContactReminderHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Il primo giro: dopo l'avvio, con Jellyfin già tranquillo.</summary>
    public static readonly TimeSpan FirstRun = TimeSpan.FromMinutes(5);

    /// <summary>Ogni quanto si guarda chi deve ricevere il promemoria.</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            contacts.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Contatti per il recupero non caricati all'avvio");
        }

        _timer = time.CreateTimer(_ => _ = RunSafelyAsync(), null, FirstRun, Interval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private async Task RunSafelyAsync()
    {
        try
        {
            await reminders.RunAsync().ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non riusciti");
        }
    }
}
