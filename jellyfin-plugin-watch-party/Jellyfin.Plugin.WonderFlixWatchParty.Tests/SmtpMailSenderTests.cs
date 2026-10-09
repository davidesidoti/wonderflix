using System.Net.Mail;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SmtpMailSenderTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private static readonly AccountMessage Message = new("WonderFlix — codice", "Il tuo codice è 123456.");
    private readonly FakeAccountSettings _settings = new();
    private readonly RecordingLogger<SmtpMailSender> _logger = new();

    private sealed record SeenMail(
        SmtpServer Server, string From, string FromName, string To, string Subject, string Body, bool Html);

    [Fact]
    public async Task APlainTextMailFromWonderFlix()
    {
        SeenMail? seen = null;
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (server, mail, _) =>
            {
                seen = new SeenMail(
                    server, mail.From!.Address, mail.From.DisplayName, mail.To.Single().Address, mail.Subject, mail.Body, mail.IsBodyHtml);
                return Task.CompletedTask;
            },
        };

        Assert.Equal(SendOutcome.Sent, await sender.SendAsync("mario@example.com", Message, Ct));

        Assert.Equal(
            new SeenMail(
                new SmtpServer("smtp.example.com", 587, "wonderflix", "smtp-secret"),
                "wonderflix@example.com",
                "WonderFlix",
                "mario@example.com",
                "WonderFlix — codice",
                "Il tuo codice è 123456.",
                false),
            seen);
    }

    [Fact]
    public async Task WithoutSettingsNothingIsSent()
    {
        var called = false;
        _settings.SmtpPassword = string.Empty;
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) =>
            {
                called = true;
                return Task.CompletedTask;
            },
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));
        Assert.False(called);
    }

    [Fact]
    public async Task AnSmtpErrorIsAFailureWithoutAddressesInTheLog()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new SmtpException(
                SmtpStatusCode.MailboxUnavailable, "Mailbox unavailable: <mario@example.com> user unknown"),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));

        var entry = Assert.Single(_logger.Entries);
        Assert.Equal(LogLevel.Warning, entry.Level);
        Assert.Contains("smtp.example.com", entry.Message);
        Assert.Contains("user unknown", entry.Message);
        Assert.DoesNotContain("mario@example.com", entry.Message);
        Assert.DoesNotContain("smtp-secret", entry.Message);
    }

    [Theory]
    [InlineData("non valido")]
    [InlineData("")]
    public async Task AnInvalidAddressIsAFailure(string to)
    {
        var sender = new SmtpMailSender(_settings, _logger) { Transport = (_, _, _) => Task.CompletedTask };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync(to, Message, Ct));
    }

    [Fact]
    public async Task NoAnswerInTimeIsAFailure()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Timeout = TimeSpan.FromMilliseconds(50),
            Transport = (_, _, ct) => Task.Delay(System.Threading.Timeout.Infinite, ct),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));
    }
}
