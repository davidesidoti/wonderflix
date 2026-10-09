using Jellyfin.Plugin.WonderFlixWatchParty.Account;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Impostazioni del recupero con tutti e due i canali configurati, da cambiare nel test.</summary>
internal sealed class FakeAccountSettings : IAccountSettings
{
    public string DiscordBotToken { get; set; } = "bot-token";

    public string DiscordGuildId { get; set; } = "123456789012345678";

    public string SmtpHost { get; set; } = "smtp.example.com";

    public int SmtpPort { get; set; } = 587;

    public string SmtpUser { get; set; } = "wonderflix";

    public string SmtpPassword { get; set; } = "smtp-secret";

    public string MailFrom { get; set; } = "wonderflix@example.com";

    public int ContactReminderDays { get; set; } = 14;
}
