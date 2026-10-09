using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Corpo degli errori degli endpoint Account (spec L §7.6).</summary>
public sealed record AccountErrorDto(
    [property: JsonPropertyName("Code")] string Code);

/// <summary>I canali configurati sul server.</summary>
public sealed record AccountChannelsDto(
    [property: JsonPropertyName("Discord")] bool Discord,
    [property: JsonPropertyName("Email")] bool Email);

/// <summary>Il proprio Discord verificato.</summary>
public sealed record DiscordContactDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("VerifiedAt")] DateTimeOffset VerifiedAt);

/// <summary>La propria email verificata, intera.</summary>
public sealed record EmailContactDto(
    [property: JsonPropertyName("Address")] string Address,
    [property: JsonPropertyName("VerifiedAt")] DateTimeOffset VerifiedAt);

/// <summary>Risposta di GET Account/Contacts e di Confirm.</summary>
public sealed record ContactsResponse(
    [property: JsonPropertyName("Channels")] AccountChannelsDto Channels,
    [property: JsonPropertyName("Discord")] DiscordContactDto? Discord,
    [property: JsonPropertyName("Email")] EmailContactDto? Email);

/// <summary>Corpo di POST Account/Contacts/{canale}/Start: nome utente Discord o email.</summary>
public sealed class LinkStartRequest
{
    [JsonPropertyName("Target")]
    public string? Target { get; set; }

    /// <summary>La password attuale dell'account (vuota se non ne ha una): senza, nessun contatto si collega.</summary>
    [JsonPropertyName("Password")]
    public string? Password { get; set; }

    /// <summary>"it" o "en": la lingua del messaggio.</summary>
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Risposta di Start: quando scade il codice.</summary>
public sealed record LinkStartResponse(
    [property: JsonPropertyName("ExpiresAt")] DateTimeOffset ExpiresAt);

/// <summary>Corpo di POST Account/Contacts/{canale}/Confirm.</summary>
public sealed class LinkConfirmRequest
{
    [JsonPropertyName("Code")]
    public string? Code { get; set; }
}

/// <summary>Corpo di POST Account/Contacts/{canale}/Unlink.</summary>
public sealed class ContactUnlinkRequest
{
    /// <summary>La password attuale dell'account (vuota se non ne ha una).</summary>
    [JsonPropertyName("Password")]
    public string? Password { get; set; }
}

/// <summary>Corpo di POST Account/Recovery/Start.</summary>
public sealed class RecoveryStartRequest
{
    [JsonPropertyName("Username")]
    public string? Username { get; set; }

    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo di POST Account/Recovery/Complete.</summary>
public sealed class RecoveryCompleteRequest
{
    [JsonPropertyName("Username")]
    public string? Username { get; set; }

    [JsonPropertyName("Code")]
    public string? Code { get; set; }

    [JsonPropertyName("NewPassword")]
    public string? NewPassword { get; set; }

    /// <summary>La lingua dell'avviso "password cambiata".</summary>
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo con la sola lingua (codice mandato dall'admin).</summary>
public sealed class AccountLanguageRequest
{
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo di POST Account/Admin/Test: nome Discord ed email facoltativi.</summary>
public sealed class AccountTestRequest
{
    [JsonPropertyName("Language")]
    public string? Language { get; set; }

    /// <summary>Un nome utente Discord a cui mandare la prova; vuoto: il Discord dell'admin.</summary>
    [JsonPropertyName("Discord")]
    public string? Discord { get; set; }

    /// <summary>Un indirizzo a cui mandare la prova; vuoto: l'email dell'admin.</summary>
    [JsonPropertyName("Email")]
    public string? Email { get; set; }
}

/// <summary>Il Discord di un utente nell'elenco dell'admin.</summary>
public sealed record AdminDiscordDto(
    [property: JsonPropertyName("Name")] string Name);

/// <summary>L'email di un utente nell'elenco dell'admin, mascherata.</summary>
public sealed record AdminEmailDto(
    [property: JsonPropertyName("Masked")] string Masked);

/// <summary>Un utente in GET Account/Admin/Users.</summary>
public sealed record AdminUserDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsAdmin")] bool IsAdmin,
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Discord")] AdminDiscordDto? Discord,
    [property: JsonPropertyName("Email")] AdminEmailDto? Email,
    [property: JsonPropertyName("LastReminderAt")] DateTimeOffset? LastReminderAt);

/// <summary>Risposta di POST Account/Admin/Users/{id}/Recovery: i canali dove è arrivato il codice.</summary>
public sealed record AdminRecoveryResponse(
    [property: JsonPropertyName("Channels")] IReadOnlyList<string> Channels);

/// <summary>L'ultimo errore d'invio di un canale.</summary>
public sealed record SendErrorDto(
    [property: JsonPropertyName("At")] DateTimeOffset At,
    [property: JsonPropertyName("Code")] string Code);

/// <summary>Lo stato di un canale.</summary>
public sealed record ChannelStatusDto(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("LastError")] SendErrorDto? LastError);

/// <summary>Risposta di GET Account/Admin/Status.</summary>
public sealed record AccountStatusResponse(
    [property: JsonPropertyName("Discord")] ChannelStatusDto Discord,
    [property: JsonPropertyName("Email")] ChannelStatusDto Email,
    [property: JsonPropertyName("WithContacts")] int WithContacts,
    [property: JsonPropertyName("Users")] int Users,
    [property: JsonPropertyName("ReminderDays")] int ReminderDays);

/// <summary>Risposta di POST Account/Admin/Test: l'esito per canale (vedi AccountTestCodes).</summary>
public sealed record AccountTestResponse(
    [property: JsonPropertyName("Discord")] string Discord,
    [property: JsonPropertyName("Email")] string Email);
