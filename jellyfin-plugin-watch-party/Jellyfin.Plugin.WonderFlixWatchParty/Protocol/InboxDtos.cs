using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi delle voci della cassetta delle notifiche (spec G §6.2).</summary>
public static class InboxEntryTypes
{
    public const string Invite = "Invite";
    public const string Announcement = "Announcement";

    /// <summary>Riepilogo di un'ondata di nuovi titoli (spec G §6.6).</summary>
    public const string NewTitles = "NewTitles";

    /// <summary>Un titolo chiesto è arrivato (spec I §7.6), a chi l'ha chiesto.</summary>
    public const string RequestAvailable = "RequestAvailable";

    /// <summary>Una richiesta da approvare (spec I §7.6), a chi può approvare.</summary>
    public const string RequestPending = "RequestPending";

    /// <summary>"Proteggi il tuo account" (spec L §7.7), a chi non ha contatti per il recupero.</summary>
    public const string ContactReminder = "ContactReminder";
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

    /// <summary>Invite: il titolo, dal nome del gruppo ("Host · Titolo"). RequestAvailable e RequestPending: il titolo da Seerr ("Dune (2021)").</summary>
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

    /// <summary>NewTitles: i film, per nome.</summary>
    [JsonPropertyName("Movies")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<NewTitleMovie>? Movies { get; set; }

    /// <summary>NewTitles: le serie seguite con i loro episodi nuovi, per nome.</summary>
    [JsonPropertyName("Series")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<NewTitleSeries>? Series { get; set; }

    /// <summary>NewTitles: film e serie oltre il tetto delle righe; manca se 0.</summary>
    [JsonPropertyName("More")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? More { get; set; }

    /// <summary>RequestAvailable, RequestPending: la richiesta in Seerr.</summary>
    [JsonPropertyName("RequestId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? RequestId { get; set; }

    /// <summary>RequestAvailable, RequestPending: "movie" o "tv".</summary>
    [JsonPropertyName("MediaType")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MediaType { get; set; }

    /// <summary>RequestAvailable, RequestPending: l'id TMDB.</summary>
    [JsonPropertyName("TmdbId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? TmdbId { get; set; }

    /// <summary>RequestAvailable, RequestPending: le stagioni chieste, per le serie.</summary>
    [JsonPropertyName("Seasons")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }

    /// <summary>RequestAvailable: il titolo nella libreria, in formato "N", se Seerr lo conosce.</summary>
    [JsonPropertyName("ItemId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ItemId { get; set; }

    /// <summary>RequestPending: chi ha chiesto il titolo.</summary>
    [JsonPropertyName("RequesterName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RequesterName { get; set; }

    /// <summary>ContactReminder: i canali che si possono collegare ("Discord", "Email").</summary>
    [JsonPropertyName("Channels")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<string>? Channels { get; set; }

    /// <summary>Copia superficiale: le liste (NewTitles, Seasons, Channels) non si cambiano mai dopo la creazione.</summary>
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

/// <summary>Un film nuovo nella voce NewTitles.</summary>
public sealed class NewTitleMovie
{
    /// <summary>L'elemento, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string ItemId { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("Year")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Year { get; set; }
}

/// <summary>Una serie seguita con i suoi episodi nuovi, nella voce NewTitles.</summary>
public sealed class NewTitleSeries
{
    /// <summary>La serie, in formato "N": la riga apre la sua scheda.</summary>
    [JsonPropertyName("SeriesId")]
    public string SeriesId { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    /// <summary>Per stagione e numero.</summary>
    [JsonPropertyName("Episodes")]
    public List<NewTitleEpisode> Episodes { get; set; } = [];
}

/// <summary>Un episodio nuovo: stagione e numero, se Jellyfin li conosce.</summary>
public sealed class NewTitleEpisode
{
    [JsonPropertyName("Season")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Season { get; set; }

    [JsonPropertyName("Episode")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Episode { get; set; }
}

/// <summary>Risposta di GET Inbox/NewTitles (admin): la casella e i titoli in attesa.</summary>
public sealed record NewTitlesStatus(
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Pending")] int Pending);

/// <summary>Risposta di POST Inbox/NewTitles/Send (admin): titoli annunciati e utenti che li hanno ricevuti.</summary>
public sealed record NewTitlesSendResponse(
    [property: JsonPropertyName("Titles")] int Titles,
    [property: JsonPropertyName("Recipients")] int Recipients);
