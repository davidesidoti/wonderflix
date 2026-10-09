using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountSettingsTests
{
    [Fact]
    public void TheDefaultsHaveNoChannelsAndRemindEveryFourteenDays()
    {
        var config = new PluginConfiguration();
        Assert.Equal(string.Empty, config.DiscordBotToken);
        Assert.Equal(string.Empty, config.DiscordGuildId);
        Assert.Equal(string.Empty, config.SmtpHost);
        Assert.Equal(587, config.SmtpPort);
        Assert.Equal(string.Empty, config.SmtpUser);
        Assert.Equal(string.Empty, config.SmtpPassword);
        Assert.Equal(string.Empty, config.MailFrom);
        Assert.Equal(14, config.ContactReminderDays);

        // Nei test Jellyfin non crea il plugin: valgono i predefiniti.
        var settings = new PluginAccountSettings();
        Assert.False(settings.IsDiscordConfigured());
        Assert.False(settings.IsEmailConfigured());
        Assert.Empty(settings.Channels());
        Assert.Equal(587, settings.SmtpPort);
        Assert.Equal(14, settings.ContactReminderDays);
    }

    [Theory]
    [InlineData(-5, 0)]
    [InlineData(0, 0)]
    [InlineData(14, 14)]
    [InlineData(365, 365)]
    [InlineData(100000, 365)]
    public void ReminderDaysStayBetweenZeroAndTheMaximum(int days, int expected) =>
        Assert.Equal(expected, AccountSettingsExtensions.ClampReminderDays(days));

    [Fact]
    public void TheSettingsSurviveTheXml()
    {
        // Jellyfin salva la configurazione con XmlSerializer.
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration
        {
            DiscordBotToken = "token",
            DiscordGuildId = "123456789012345678",
            SmtpHost = "smtp.example.com",
            SmtpPort = 2525,
            SmtpUser = "user",
            SmtpPassword = "password",
            MailFrom = "wonderflix@example.com",
            ContactReminderDays = 0,
        });
        using var reader = new StringReader(writer.ToString());

        var read = (PluginConfiguration)serializer.Deserialize(reader)!;

        Assert.Equal("token", read.DiscordBotToken);
        Assert.Equal("123456789012345678", read.DiscordGuildId);
        Assert.Equal("smtp.example.com", read.SmtpHost);
        Assert.Equal(2525, read.SmtpPort);
        Assert.Equal("user", read.SmtpUser);
        Assert.Equal("password", read.SmtpPassword);
        Assert.Equal("wonderflix@example.com", read.MailFrom);
        Assert.Equal(0, read.ContactReminderDays);
    }

    [Fact]
    public void BothChannelsWhenEverythingIsThere()
    {
        var settings = new FakeAccountSettings();

        Assert.True(settings.IsDiscordConfigured());
        Assert.True(settings.IsEmailConfigured());
        Assert.True(settings.IsConfigured(AccountChannel.Email));
        Assert.Equal(new[] { AccountChannel.Discord, AccountChannel.Email }, settings.Channels());
    }

    [Theory]
    [InlineData("", "123456789012345678")]
    [InlineData(" ", "123456789012345678")]
    [InlineData("token", "")]
    [InlineData("token", "server")]
    [InlineData("token", "1234")]
    public void DiscordNeedsATokenAndANumericServerId(string token, string guild) =>
        Assert.False(new FakeAccountSettings { DiscordBotToken = token, DiscordGuildId = guild }.IsDiscordConfigured());

    [Theory]
    [InlineData("", 587, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 0, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 70000, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 587, "", "p", "f@example.com")]
    [InlineData("smtp.example.com", 587, "u", "", "f@example.com")]
    [InlineData("smtp.example.com", 587, "u", "p", " ")]
    public void EmailNeedsServerPortUserPasswordAndSender(string host, int port, string user, string password, string from)
    {
        var settings = new FakeAccountSettings
        {
            SmtpHost = host,
            SmtpPort = port,
            SmtpUser = user,
            SmtpPassword = password,
            MailFrom = from,
        };

        Assert.False(settings.IsEmailConfigured());
        Assert.Equal(new[] { AccountChannel.Discord }, settings.Channels());
    }
}
