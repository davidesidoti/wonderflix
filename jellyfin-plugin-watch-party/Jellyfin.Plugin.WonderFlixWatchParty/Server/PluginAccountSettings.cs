using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le impostazioni del recupero dalla configurazione del plugin.</summary>
public sealed class PluginAccountSettings : IAccountSettings
{
    // Senza plugin (nei test) valgono i predefiniti.
    private static readonly PluginConfiguration Defaults = new();

    // Si legge ogni volta, come PluginSeerrSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione.
    private static PluginConfiguration Config => Plugin.Instance?.Configuration ?? Defaults;

    public string DiscordBotToken => (Config.DiscordBotToken ?? string.Empty).Trim();

    public string DiscordGuildId => (Config.DiscordGuildId ?? string.Empty).Trim();

    public string SmtpHost => (Config.SmtpHost ?? string.Empty).Trim();

    public int SmtpPort => Config.SmtpPort;

    public string SmtpUser => (Config.SmtpUser ?? string.Empty).Trim();

    // La password si usa com'è: gli spazi possono farne parte.
    public string SmtpPassword => Config.SmtpPassword ?? string.Empty;

    public string MailFrom => (Config.MailFrom ?? string.Empty).Trim();

    public int ContactReminderDays => AccountSettingsExtensions.ClampReminderDays(Config.ContactReminderDays);
}
