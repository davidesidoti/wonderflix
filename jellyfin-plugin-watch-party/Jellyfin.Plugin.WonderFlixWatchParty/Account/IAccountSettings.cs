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

    /// <summary>Token e id numerico del server.</summary>
    public static bool IsDiscordConfigured(this IAccountSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.DiscordBotToken) && DiscordIds.IsSnowflake(settings.DiscordGuildId);

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
