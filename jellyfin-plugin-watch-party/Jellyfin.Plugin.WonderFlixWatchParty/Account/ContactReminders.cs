using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// I promemoria "Proteggi il tuo account" (spec L §7.7): ogni N giorni, a chi
/// non ha contatti verificati. Solo utenti attivi e non admin, e solo con
/// almeno un canale configurato. Toglie anche i contatti degli utenti che
/// Jellyfin non ha più.
/// </summary>
public sealed class ContactReminders(
    IUserDirectory users,
    ContactRegistry contacts,
    InboxService inbox,
    IAccountSettings settings,
    TimeProvider time,
    ILogger<ContactReminders> logger)
{
    /// <summary>
    /// Quanto prima di N giorni si può rimandare un promemoria: il timer gira
    /// ogni 24 ore e qualche millisecondo di ritardo non deve spostare il
    /// promemoria di un giorno.
    /// </summary>
    public static readonly TimeSpan ReminderTolerance = TimeSpan.FromHours(1);

    /// <summary>Manda i promemoria dovuti; restituisce quanti.</summary>
    public async Task<int> RunAsync()
    {
        var all = users.GetUsers();

        // La pulizia viene prima dello stop dei promemoria: le email degli utenti cancellati non
        // restano nel file anche con i promemoria spenti o senza canali.
        // Un elenco vuoto (errore momentaneo di Jellyfin) toglierebbe i contatti di tutti.
        if (all.Count > 0)
        {
            var known = all.Select(u => u.Id).ToHashSet();
            contacts.Prune(known.Contains);
        }

        var days = settings.ContactReminderDays;
        var channels = settings.Channels();
        if (days <= 0 || channels.Count == 0)
        {
            return 0;
        }

        var now = time.GetUtcNow();
        var every = TimeSpan.FromDays(days) - ReminderTolerance;
        var names = channels.Select(c => c.Name()).ToList();
        var sent = 0;
        foreach (var user in all.Where(u => u.Enabled && !u.IsAdmin))
        {
            // Un contatto su un canale spento non serve al recupero: è come non averlo.
            var mine = contacts.Get(user.Id);
            if (settings.HasReachableContact(mine) || (mine.LastReminderAt is { } last && now - last < every))
            {
                continue;
            }

            await inbox.AddContactReminderAsync(user.Id, names).ConfigureAwait(false);
            contacts.MarkReminded(user.Id, now);
            sent++;
        }

        if (sent > 0)
        {
            logger.LogInformation("Promemoria dei contatti a {Count} utenti", sent);
        }

        return sent;
    }
}
