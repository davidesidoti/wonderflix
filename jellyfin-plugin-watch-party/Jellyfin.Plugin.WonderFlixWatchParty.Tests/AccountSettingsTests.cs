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

    // Il file XML di un server con il plugin 1.5.0: ci sono solo i nuovi titoli e Seerr.
    private const string Xml150 = """
        <?xml version="1.0" encoding="utf-8"?>
        <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <NotifyNewTitles>false</NotifyNewTitles>
          <SeerrUrl>https://example.com/seerr</SeerrUrl>
          <SeerrApiKey>chiave-seerr</SeerrApiKey>
          <SeerrWebhookSecret>segreto-seerr</SeerrWebhookSecret>
        </PluginConfiguration>
        """;

    private static PluginConfiguration ReadXml(string xml)
    {
        // Come fa Jellyfin: XmlSerializer sul testo del file.
        using var reader = new StringReader(xml);
        return (PluginConfiguration)new XmlSerializer(typeof(PluginConfiguration)).Deserialize(reader)!;
    }

    [Fact]
    public void AnXmlFromVersion150KeepsItsValuesAndGetsTheNewDefaults()
    {
        var read = ReadXml(Xml150);

        Assert.False(read.NotifyNewTitles);
        Assert.Equal("https://example.com/seerr", read.SeerrUrl);
        Assert.Equal("chiave-seerr", read.SeerrApiKey);
        Assert.Equal("segreto-seerr", read.SeerrWebhookSecret);
        Assert.Equal(587, read.SmtpPort);
        Assert.Equal(14, read.ContactReminderDays);
        Assert.Equal(string.Empty, read.DiscordBotToken);
        Assert.Equal(string.Empty, read.SmtpHost);
    }

    // È quello che fa la prova sul server: una riga aggiunta con sed prima della chiusura.
    [Fact]
    public void TheReminderLineAddedBeforeTheClosingTagIsRead()
    {
        var edited = Xml150.Replace(
            "</PluginConfiguration>", "  <ContactReminderDays>0</ContactReminderDays>\n</PluginConfiguration>", StringComparison.Ordinal);

        var read = ReadXml(edited);

        Assert.Equal(0, read.ContactReminderDays);
        Assert.Equal("chiave-seerr", read.SeerrApiKey);
        Assert.Equal(587, read.SmtpPort);
        Assert.False(read.NotifyNewTitles);
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

    // Un contatto su un canale spento non serve al recupero: conta solo quello che si può raggiungere adesso.
    [Theory]
    [InlineData(true, true, true, true, true)]
    [InlineData(true, true, false, true, true)]
    [InlineData(true, true, true, false, true)]
    [InlineData(false, true, true, true, true)]
    [InlineData(true, false, true, true, true)]
    [InlineData(true, false, false, true, false)]
    [InlineData(false, true, true, false, false)]
    [InlineData(false, false, true, true, false)]
    [InlineData(true, true, false, false, false)]
    public void AContactCountsOnlyOnAChannelThatIsOn(
        bool hasDiscord, bool hasEmail, bool discordOn, bool emailOn, bool reachable)
    {
        var settings = new FakeAccountSettings();
        if (!discordOn)
        {
            settings.DiscordBotToken = string.Empty;
        }

        if (!emailOn)
        {
            settings.SmtpHost = string.Empty;
        }

        var contacts = new UserContacts
        {
            Discord = hasDiscord ? new DiscordContact { Id = "222222222222222222", Name = "mario" } : null,
            Email = hasEmail ? new EmailContact { Address = "mario@example.com" } : null,
        };

        Assert.Equal(reachable, settings.HasReachableContact(contacts));
        Assert.Equal(reachable, settings.ReachableTargets(contacts).Count > 0);
    }

    [Fact]
    public void TheReachableTargetsAreInTheOrderOfTheChannels()
    {
        var settings = new FakeAccountSettings();
        var contacts = new UserContacts
        {
            Discord = new DiscordContact { Id = "222222222222222222", Name = "mario" },
            Email = new EmailContact { Address = "mario@example.com" },
        };

        Assert.Equal(
            new[] { (AccountChannel.Discord, "222222222222222222"), (AccountChannel.Email, "mario@example.com") },
            settings.ReachableTargets(contacts));
        settings.SmtpHost = string.Empty;
        Assert.Equal(new[] { (AccountChannel.Discord, "222222222222222222") }, settings.ReachableTargets(contacts));
    }

    [Theory]
    [InlineData("", "123456789012345678")]
    [InlineData(" ", "123456789012345678")]
    [InlineData("token", "")]
    [InlineData("token", "server")]
    [InlineData("token", "1234")]
    public void DiscordNeedsATokenAndANumericServerId(string token, string guild) =>
        Assert.False(new FakeAccountSettings { DiscordBotToken = token, DiscordGuildId = guild }.IsDiscordConfigured());

    // Il token va in un'intestazione HTTP: spazi, a capo o altri simboli non sono un token.
    [Theory]
    [InlineData("tok en")]
    [InlineData("token\nX-Injected: 1")]
    [InlineData("token\n")]
    [InlineData("token\r\n")]
    [InlineData("tok:en")]
    [InlineData("tökén")]
    [InlineData("Bot token")]
    public void ATokenThatIsNotMadeOfTokenCharactersIsNotConfigured(string token) =>
        Assert.False(new FakeAccountSettings { DiscordBotToken = token }.IsDiscordConfigured());

    [Theory]
    [InlineData("bot-token")]
    [InlineData("MTIzNDU2Nzg5MDEyMzQ1Njc4.GabcDE.abc_def-GHI0123456789")]
    public void ATokenMadeOfBase64UrlSegmentsIsConfigured(string token) =>
        Assert.True(new FakeAccountSettings { DiscordBotToken = token }.IsDiscordConfigured());

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
