using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi delle voci della cassetta delle notifiche (spec G §6.2).</summary>
public static class InboxEntryTypes
{
    public const string Invite = "Invite";
    public const string Announcement = "Announcement";
}

/// <summary>
/// Una voce della cassetta delle notifiche (spec G §6.2): la stessa forma in
/// inbox.json e nelle risposte di GET Inbox. I campi di un tipo mancano
/// negli altri. Si cambia solo sotto il lock di InboxService; fuori di lì
/// girano copie (<see cref="Copy"/>).
/// </summary>
public sealed class InboxEntry
{
    [JsonPropertyName("Id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Progressivo per utente: cresce a ogni voce nuova o aggiornata.</summary>
    [JsonPropertyName("Seq")]
    public long Seq { get; set; }

    [JsonPropertyName("Type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("Read")]
    public bool Read { get; set; }

    /// <summary>Invite: il gruppo SyncPlay, in formato "N".</summary>
    [JsonPropertyName("GroupId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? GroupId { get; set; }

    /// <summary>Invite: chi ha invitato.</summary>
    [JsonPropertyName("FromName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromName { get; set; }

    /// <summary>Invite: il titolo, dal nome del gruppo ("Host · Titolo").</summary>
    [JsonPropertyName("Title")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Title { get; set; }

    /// <summary>Invite: l'elemento della locandina (la serie, per un episodio), in formato "N".</summary>
    [JsonPropertyName("ImageItemId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ImageItemId { get; set; }

    /// <summary>Announcement: il testo dell'admin.</summary>
    [JsonPropertyName("Text")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Text { get; set; }

    public InboxEntry Copy() => (InboxEntry)MemberwiseClone();
}

/// <summary>Risposta di GET Inbox: le voci dalla più recente e quante non lette.</summary>
public sealed record InboxResponse(
    [property: JsonPropertyName("Entries")] IReadOnlyList<InboxEntry> Entries,
    [property: JsonPropertyName("Unread")] int Unread);

/// <summary>Corpo di POST Inbox/Read: segna lette le voci fino a questo Seq.</summary>
public sealed class InboxReadRequest
{
    [JsonPropertyName("UpTo")]
    public long UpTo { get; set; }
}

/// <summary>Corpo di POST Inbox/Announcements.</summary>
public sealed class AnnouncementRequest
{
    [JsonPropertyName("Text")]
    public string? Text { get; set; }
}

/// <summary>Risposta di POST Inbox/Announcements: a quanti utenti è arrivato.</summary>
public sealed record AnnouncementResponse(
    [property: JsonPropertyName("Recipients")] int Recipients);
