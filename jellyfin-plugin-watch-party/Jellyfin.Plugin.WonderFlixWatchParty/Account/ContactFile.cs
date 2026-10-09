using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Il Discord verificato di un utente.</summary>
public sealed class DiscordContact
{
    /// <summary>L'id dell'utente Discord (snowflake).</summary>
    [JsonPropertyName("Id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Il nome utente Discord al momento della verifica.</summary>
    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("VerifiedAt")]
    public DateTimeOffset VerifiedAt { get; set; }
}

/// <summary>L'email verificata di un utente, come l'ha scritta.</summary>
public sealed class EmailContact
{
    [JsonPropertyName("Address")]
    public string Address { get; set; } = string.Empty;

    [JsonPropertyName("VerifiedAt")]
    public DateTimeOffset VerifiedAt { get; set; }
}

/// <summary>
/// I contatti verificati di un utente e l'ultimo promemoria (spec L §7.2):
/// la stessa forma in contacts.json e in memoria. Fuori dal registro girano
/// solo copie (<see cref="Copy"/>).
/// </summary>
public sealed class UserContacts
{
    [JsonPropertyName("Discord")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DiscordContact? Discord { get; set; }

    [JsonPropertyName("Email")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public EmailContact? Email { get; set; }

    /// <summary>Quando è arrivato l'ultimo promemoria "Proteggi il tuo account".</summary>
    [JsonPropertyName("LastReminderAt")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTimeOffset? LastReminderAt { get; set; }

    /// <summary>Almeno un contatto verificato.</summary>
    [JsonIgnore]
    public bool HasContact => Discord is not null || Email is not null;

    /// <summary>Copia profonda.</summary>
    public UserContacts Copy() => new()
    {
        Discord = Discord is null ? null : new DiscordContact { Id = Discord.Id, Name = Discord.Name, VerifiedAt = Discord.VerifiedAt },
        Email = Email is null ? null : new EmailContact { Address = Email.Address, VerifiedAt = Email.VerifiedAt },
        LastReminderAt = LastReminderAt,
    };
}

/// <summary>
/// Contenuto di contacts.json (spec L §7.2). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="ContactStore.Load"/>.
/// </summary>
public sealed class ContactFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, UserContacts?>? Users { get; set; } = [];
}
