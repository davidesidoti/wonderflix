using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un avviso agli admin (spec V). <paramref name="Key"/> lo tiene uno per volta
/// nella cassetta (<see cref="InboxEntry.AlertKey"/>).
/// </summary>
public sealed record AdminAlert(
    string Key, string Type, string Title, string? Reason = null, int? Percent = null, string? UserName = null, string? Scope = null);

/// <summary>
/// Le voci degli admin attivi per chiave (spec V): quelle che restano finché
/// il problema c'è (<see cref="SyncAsync"/>) e quelle di storico
/// (<see cref="RaiseAsync"/>). Non lancia: gli errori finiscono nel log.
/// </summary>
public sealed class AdminAlerts(InboxService inbox, IUserDirectory users, TimeProvider time, ILogger<AdminAlerts> logger)
{
    /// <summary>
    /// Allinea le voci con le chiavi che cominciano con keyPrefix a current:
    /// toglie quelle che non ci sono più, aggiorna sul posto quelle con la
    /// stessa chiave, lo stesso tipo e lo stesso motivo (senza push), sostituisce
    /// le altre con una voce nuova (con push).
    /// </summary>
    public async Task SyncAsync(string keyPrefix, IReadOnlyList<AdminAlert> current)
    {
        try
        {
            var entries = current.Select(ToEntry).ToList();
            await inbox.SyncAlertsAsync(Admins(), keyPrefix, entries).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avvisi agli admin {Prefix} non allineati", keyPrefix);
        }
    }

    /// <summary>Una voce nuova di storico per ogni admin attivo; non si toglie da sola.</summary>
    public async Task RaiseAsync(AdminAlert alert)
    {
        try
        {
            await inbox.AddAlertAsync(Admins(), ToEntry(alert)).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso agli admin {Key} non creato", alert.Key);
        }
    }

    private List<Guid> Admins() => users.GetUsers().Where(u => u.IsAdmin && u.Enabled).Select(u => u.Id).ToList();

    private InboxEntry ToEntry(AdminAlert alert) => new()
    {
        Type = alert.Type,
        CreatedAt = time.GetUtcNow(),
        AlertKey = alert.Key,
        Title = alert.Title,
        Reason = alert.Reason,
        Percent = alert.Percent,
        UserName = alert.UserName,
        Scope = alert.Scope,
    };
}
