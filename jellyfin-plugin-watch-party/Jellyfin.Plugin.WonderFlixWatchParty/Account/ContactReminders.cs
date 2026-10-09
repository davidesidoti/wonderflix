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
    /// <summary>Manda i promemoria dovuti; restituisce quanti.</summary>
    public async Task<int> RunAsync()
    {
        var days = settings.ContactReminderDays;
        var channels = settings.Channels();
        if (days <= 0 || channels.Count == 0)
        {
            return 0;
        }

        var all = users.GetUsers();

        // Un elenco vuoto (errore momentaneo di Jellyfin) toglierebbe i contatti di tutti.
        if (all.Count > 0)
        {
            var known = all.Select(u => u.Id).ToHashSet();
            contacts.Prune(known.Contains);
        }

        var now = time.GetUtcNow();
        var every = TimeSpan.FromDays(days);
        var names = channels.Select(c => c.Name()).ToList();
        var sent = 0;
        foreach (var user in all.Where(u => u.Enabled && !u.IsAdmin))
        {
            var mine = contacts.Get(user.Id);
            if (mine.HasContact || (mine.LastReminderAt is { } last && now - last < every))
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
