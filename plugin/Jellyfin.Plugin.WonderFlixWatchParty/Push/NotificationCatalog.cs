using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>A chi arriva un tipo di notifica (spec V).</summary>
public enum NotificationAudience
{
    Everyone,
    Approvers,
    Admins,
}

/// <summary>Il testo di una push e la rotta dell'app da aprire (senza '#').</summary>
public sealed record PushMessage(string Title, string Body, string Route);

/// <summary>
/// I tipi di notifica push (spec V): a chi vanno, il testo in italiano e in
/// inglese, la rotta. Niente dati sensibili nei testi: solo campi della voce
/// che l'utente vede già nella cassetta.
/// </summary>
public static class NotificationCatalog
{
    /// <summary>
    /// Caratteri (text element) al massimo nel testo: un annuncio lungo non deve superare il limite del payload
    /// cifrato né i 4096 byte di Apple.
    /// </summary>
    public const int MaxBodyLength = 200;

    // Sceglie il testo nella lingua della sottoscrizione.
    private delegate string Pick(string it, string en);

    private sealed record Spec(string Type, NotificationAudience Audience, Func<InboxEntry, Pick, PushMessage> Build);

    // Prima "tutti", poi chi approva, poi gli admin: è l'ordine della pagina delle preferenze.
    private static readonly Spec[] Specs =
    [
        new(InboxEntryTypes.Invite, NotificationAudience.Everyone, (e, t) =>
            new(t($"{e.FromName} ti invita a un watch party", $"{e.FromName} invited you to a watch party"), e.Title ?? "", "/inbox")),
        new(InboxEntryTypes.Announcement, NotificationAudience.Everyone, (e, t) =>
            new(t("Annuncio", "Announcement"), e.Text ?? "", "/inbox")),
        new(InboxEntryTypes.NewTitles, NotificationAudience.Everyone, (e, t) =>
            new(t("Nuovi titoli su WonderFlix", "New on WonderFlix"), FirstNames(e), "/home")),
        new(InboxEntryTypes.RequestAvailable, NotificationAudience.Everyone, (e, t) =>
            new(t("Ora disponibile", "Now available"), e.Title ?? "", string.IsNullOrEmpty(e.ItemId) ? "/requests" : $"/item/{e.ItemId}")),
        new(InboxEntryTypes.RequestApproved, NotificationAudience.Everyone, (e, t) =>
            new(t("Richiesta accettata", "Request approved"), e.Title ?? "", "/requests")),
        new(InboxEntryTypes.RequestDeclined, NotificationAudience.Everyone, (e, t) =>
            new(t("Richiesta rifiutata", "Request declined"), e.Title ?? "", "/requests")),
        new(InboxEntryTypes.ContactReminder, NotificationAudience.Everyone, (e, t) =>
            new(t("Proteggi il tuo account", "Protect your account"),
                t("Aggiungi un contatto per recuperare la password", "Add a contact to recover your password"), "/settings")),
        new(InboxEntryTypes.Recommendation, NotificationAudience.Everyone, (e, t) =>
            new(t($"{e.FromName} ti consiglia un titolo", $"{e.FromName} recommends a title"), e.Title ?? "",
                string.IsNullOrEmpty(e.ItemId) ? "/inbox" : $"/item/{e.ItemId}")),
        new(InboxEntryTypes.MatchInvite, NotificationAudience.Everyone, (e, t) =>
            new(t($"{e.FromName} ti invita a un match", $"{e.FromName} invited you to a match"),
                t("Scegliete insieme cosa guardare", "Pick something to watch together"),
                string.IsNullOrEmpty(e.RoomId) ? "/inbox" : $"/match/{e.RoomId}")),
        new(InboxEntryTypes.ReportResolved, NotificationAudience.Everyone, (e, t) =>
            new(t("Segnalazione chiusa", "Report closed"), e.Title ?? "", "/inbox")),
        new(InboxEntryTypes.RequestPending, NotificationAudience.Approvers, (e, t) =>
            new(t("Nuova richiesta da approvare", "New request to approve"),
                t($"{e.Title} — da {e.RequesterName}", $"{e.Title} — from {e.RequesterName}"), "/requests")),
        new(InboxEntryTypes.ReportPending, NotificationAudience.Admins, (e, t) =>
            new(t("Nuova segnalazione", "New report"),
                t($"{e.Title} — da {e.FromName}", $"{e.Title} — from {e.FromName}"), "/admin?tab=wonderflix")),
        new(InboxEntryTypes.DownloadNeedsYou, NotificationAudience.Admins, (e, t) =>
            new(t("Download da sistemare", "Download needs you"), $"{e.Title} — {DownloadReason(e.Reason, t)}", "/admin?tab=downloads")),
        new(InboxEntryTypes.DownloadStalled, NotificationAudience.Admins, (e, t) =>
            new(t("Download fermo", "Download stalled"),
                t($"{e.Title} — tolto dalla coda", $"{e.Title} — removed from the queue"), "/admin?tab=downloads")),
        new(InboxEntryTypes.LightenBlocked, NotificationAudience.Admins, (e, t) =>
            new(t("Alleggerisci bloccato", "Lighten blocked"),
                t($"{e.Title} — import da fare a mano", $"{e.Title} — manual import needed"), "/admin?tab=space")),
        new(InboxEntryTypes.SpaceOperationFailed, NotificationAudience.Admins, (e, t) =>
            new(t("Pulizia dello spazio fallita", "Space cleanup failed"),
                t("Apri la scheda Spazio per i dettagli", "Open the Space tab for details"), "/admin?tab=space")),
        new(InboxEntryTypes.DiskAlmostFull, NotificationAudience.Admins, (e, t) =>
            new(t("Disco quasi pieno", "Disk almost full"),
                t($"Usato il {e.Percent}% della quota", $"{e.Percent}% of the quota used"), "/admin?tab=space")),
        new(InboxEntryTypes.RecoveryStarted, NotificationAudience.Admins, (e, t) =>
            new(t("Recupero password avviato", "Password recovery started"), e.UserName ?? "", "/admin?tab=users")),
        new(InboxEntryTypes.RecoveryBlocked, NotificationAudience.Admins, (e, t) =>
            new(t("Recupero password bloccato", "Password recovery blocked"),
                e.Scope == InboxScopes.Everyone
                    ? t("Troppi tentativi: bloccato per tutti", "Too many attempts: blocked for everyone")
                    : t($"Troppi tentativi per {e.UserName}", $"Too many attempts for {e.UserName}"),
                "/admin?tab=users")),
        new(InboxEntryTypes.RestartPending, NotificationAudience.Admins, (e, t) =>
            new(t("Jellyfin chiede un riavvio", "Jellyfin needs a restart"),
                t("Riavvia il server dalla dashboard admin", "Restart the server from the admin dashboard"), "/admin")),
    ];

    private static readonly Dictionary<string, Spec> ByType = Specs.ToDictionary(s => s.Type);

    /// <summary>Tutti i tipi, nell'ordine della pagina delle preferenze.</summary>
    public static IReadOnlyList<string> Types { get; } = Specs.Select(s => s.Type).ToList();

    /// <summary>A chi va il tipo; un tipo sconosciuto vale admin, il più riservato.</summary>
    public static NotificationAudience AudienceOf(string type) =>
        ByType.TryGetValue(type, out var spec) ? spec.Audience : NotificationAudience.Admins;

    /// <summary>
    /// Il testo della push per la voce; null per un tipo sconosciuto. Una
    /// lingua diversa da "it" vale "en". Un campo mancante diventa vuoto. Il
    /// testo si taglia a <see cref="MaxBodyLength"/>, con "…" in fondo.
    /// </summary>
    public static PushMessage? Message(InboxEntry entry, string language)
    {
        if (!ByType.TryGetValue(entry.Type, out var spec))
        {
            return null;
        }

        var italian = language == "it";
        var message = spec.Build(entry, (it, en) => italian ? it : en);
        var body = new StringInfo(message.Body);
        return body.LengthInTextElements <= MaxBodyLength
            ? message
            : message with { Body = body.SubstringByTextElements(0, MaxBodyLength - 1) + "…" };
    }

    // I primi 3 nomi, prima i film poi le serie.
    private static string FirstNames(InboxEntry entry) =>
        string.Join(", ", (entry.Movies ?? []).Select(m => m.Name).Concat((entry.Series ?? []).Select(s => s.Name)).Take(3));

    // Un motivo nuovo che il catalogo non conosce ancora esce com'è.
    private static string DownloadReason(string? reason, Pick t) => reason switch
    {
        "NothingFound" => t("nessun risultato", "nothing found"),
        "BelowMinScore" => t("punteggio sotto il minimo", "score below minimum"),
        "GrabRefused" => t("grab rifiutato", "grab refused"),
        "SearchFailed" => t("ricerca fallita", "search failed"),
        "ImportBlocked" => t("import da fare a mano", "manual import needed"),
        _ => reason ?? "",
    };
}
