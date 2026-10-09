namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Le impostazioni del recupero (spec L §7.1). Vanno lette ogni volta:
/// l'admin le cambia dalla Dashboard.
/// </summary>
public interface IAccountSettings
{
    string DiscordBotToken { get; }

    string DiscordGuildId { get; }

    string SmtpHost { get; }

    int SmtpPort { get; }

    string SmtpUser { get; }

    string SmtpPassword { get; }

    string MailFrom { get; }

    /// <summary>Ogni quanti giorni il promemoria; 0 lo spegne.</summary>
    int ContactReminderDays { get; }
}

public static class AccountSettingsExtensions
{
    /// <summary>Porta TCP più alta.</summary>
    private const int MaxPort = 65535;

    /// <summary>
    /// Giorni massimi fra due promemoria: come il massimo della pagina. Un
    /// valore enorme scritto a mano nel file farebbe lanciare TimeSpan.FromDays.
    /// </summary>
    public const int MaxContactReminderDays = 365;

    /// <summary>I giorni del promemoria portati fra 0 (spento) e il massimo.</summary>
    internal static int ClampReminderDays(int days) => Math.Clamp(days, 0, MaxContactReminderDays);

    /// <summary>Token (nella forma di un token) e id numerico del server.</summary>
    public static bool IsDiscordConfigured(this IAccountSettings settings) =>
        IsTokenShaped(settings.DiscordBotToken) && DiscordIds.IsSnowflake(settings.DiscordGuildId);

    // Un token di Discord è fatto di segmenti base64url uniti da punti, e va in un'intestazione HTTP:
    // con spazi o a capo non è un token, e non deve poter aggiungere altre intestazioni.
    // Il controllo è carattere per carattere (una regex con "$" accetterebbe un "\n" finale).
    private static bool IsTokenShaped(string? token) =>
        !string.IsNullOrEmpty(token) && token.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');

    /// <summary>Server, porta, utente, password e mittente.</summary>
    public static bool IsEmailConfigured(this IAccountSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.SmtpHost)
        && settings.SmtpPort is > 0 and <= MaxPort
        && !string.IsNullOrWhiteSpace(settings.SmtpUser)
        && !string.IsNullOrEmpty(settings.SmtpPassword)
        && !string.IsNullOrWhiteSpace(settings.MailFrom);

    public static bool IsConfigured(this IAccountSettings settings, AccountChannel channel) =>
        channel == AccountChannel.Discord ? settings.IsDiscordConfigured() : settings.IsEmailConfigured();

    /// <summary>I canali configurati, nell'ordine Discord, Email.</summary>
    public static IReadOnlyList<AccountChannel> Channels(this IAccountSettings settings) =>
        AccountChannels.All.Where(settings.IsConfigured).ToList();
}
