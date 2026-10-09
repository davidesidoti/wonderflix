using System.Diagnostics;
using System.Net;
using System.Net.Mail;
using System.Net.Sockets;
using System.Text;
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

    [Fact]
    public async Task AnyErrorButTheCallersCancellationIsAFailure()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new InvalidCastException("non previsto"),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));

        var cancelling = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, ct) => Task.Delay(System.Threading.Timeout.Infinite, ct),
        };
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => cancelling.SendAsync("mario@example.com", Message, cancelled.Token));
    }

    [Fact]
    public async Task TheRootCauseGoesToTheLogWithoutAddresses()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new SmtpException(
                "Failure sending mail.",
                new IOException("Unable to read data", new TimeoutException("root cause for <mario@example.com>"))),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));

        var entry = Assert.Single(_logger.Entries);
        Assert.Contains("SmtpException", entry.Message);
        Assert.Contains("Failure sending mail.", entry.Message);
        Assert.Contains("TimeoutException", entry.Message);
        Assert.Contains("root cause for <[email]>", entry.Message);
        Assert.DoesNotContain("mario@example.com", entry.Message);
        Assert.DoesNotContain("smtp-secret", entry.Message);
    }

    [Fact]
    public void TheServerDescriptionHidesThePassword()
    {
        var server = new SmtpServer("smtp.example.com", 587, "wonderflix", "smtp-secret");

        Assert.Equal("SmtpServer { Host = smtp.example.com, Port = 587, User = wonderflix }", server.ToString());
        Assert.DoesNotContain("smtp-secret", server.ToString());
    }

    [Fact]
    public async Task OnPort465TheFailureSaysImplicitTlsIsNotSupported()
    {
        _settings.SmtpPort = 465;
        var timingOut = new SmtpMailSender(_settings, _logger)
        {
            Timeout = TimeSpan.FromMilliseconds(50),
            Transport = (_, _, ct) => Task.Delay(System.Threading.Timeout.Infinite, ct),
        };
        var failing = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new SmtpException(SmtpStatusCode.GeneralFailure, "Failure sending mail."),
        };

        Assert.Equal(SendOutcome.Failed, await timingOut.SendAsync("mario@example.com", Message, Ct));
        Assert.Equal(SendOutcome.Failed, await failing.SendAsync("mario@example.com", Message, Ct));

        Assert.Equal(2, _logger.Entries.Count);
        Assert.All(_logger.Entries, e =>
        {
            Assert.Contains("la porta 465 (TLS implicito) non è supportata: usa la 587 con STARTTLS", e.Message);
        });
    }

    [Fact]
    public async Task OnOtherPortsThereIsNoPort465Hint()
    {
        var timingOut = new SmtpMailSender(_settings, _logger)
        {
            Timeout = TimeSpan.FromMilliseconds(50),
            Transport = (_, _, ct) => Task.Delay(System.Threading.Timeout.Infinite, ct),
        };
        var failing = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new SmtpException(SmtpStatusCode.GeneralFailure, "Failure sending mail."),
        };

        await timingOut.SendAsync("mario@example.com", Message, Ct);
        await failing.SendAsync("mario@example.com", Message, Ct);

        Assert.Equal(2, _logger.Entries.Count);
        Assert.All(_logger.Entries, e => Assert.DoesNotContain("465", e.Message));
    }

    // Le prove sul trasporto vero: un server SMTP finto su 127.0.0.1, in una porta scelta dal sistema.
    [Fact]
    public async Task ASilentServerIsAFailureWhenTheTimeIsUp()
    {
        using var server = new LoopbackSmtpServer(greets: false);
        server.PointSettingsAt(_settings);
        var sender = new SmtpMailSender(_settings, _logger) { Timeout = TimeSpan.FromMilliseconds(500) };
        var started = Stopwatch.StartNew();

        var outcome = await sender.SendAsync("mario@example.com", Message, Ct).WaitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(SendOutcome.Failed, outcome);
        // Il limite vero è WaitAsync (10 s). Questo solo distingue i 500 ms dai 15 s predefiniti, con margine per un CI lento.
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(8), $"ci ha messo {started.Elapsed}");
        Assert.Contains("nessuna risposta", Assert.Single(_logger.Entries).Message);
    }

    [Fact]
    public async Task AServerWithoutStartTlsIsAFailureAndGetsNeitherPasswordNorMail()
    {
        using var server = new LoopbackSmtpServer(greets: true);
        server.PointSettingsAt(_settings);
        var sender = new SmtpMailSender(_settings, _logger);

        var outcome = await sender.SendAsync("mario@example.com", Message, Ct).WaitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(SendOutcome.Failed, outcome);
        var received = server.Received;
        Assert.Contains(received, line => line.StartsWith("EHLO", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(
            received,
            line => line.StartsWith("AUTH", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("MAIL", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("RCPT", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("DATA", StringComparison.OrdinalIgnoreCase));
        var entry = Assert.Single(_logger.Entries);
        Assert.Contains("SmtpException", entry.Message);
        Assert.DoesNotContain("smtp-secret", entry.Message);
    }

    /// <summary>
    /// Un server SMTP finto su 127.0.0.1: accetta un solo client. Muto, oppure
    /// saluta con 220 e risponde a EHLO con 250 senza STARTTLS. Registra le righe ricevute.
    /// </summary>
    private sealed class LoopbackSmtpServer : IDisposable
    {
        private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource _stop = new();
        private readonly List<string> _received = [];
        private readonly Task _run;

        public LoopbackSmtpServer(bool greets)
        {
            _listener.Start();
            _run = Task.Run(() => RunAsync(greets));
        }

        public int Port => ((IPEndPoint)_listener.LocalEndpoint).Port;

        public IReadOnlyList<string> Received
        {
            get
            {
                lock (_received)
                {
                    return _received.ToList();
                }
            }
        }

        public void PointSettingsAt(FakeAccountSettings settings)
        {
            settings.SmtpHost = "127.0.0.1";
            settings.SmtpPort = Port;
        }

        public void Dispose()
        {
            _stop.Cancel();
            _listener.Stop();
            try
            {
                _run.Wait(TimeSpan.FromSeconds(5));
            }
            catch (AggregateException)
            {
                // RunAsync prende già gli errori attesi alla chiusura.
            }

            _stop.Dispose();
        }

        private async Task RunAsync(bool greets)
        {
            try
            {
                using var client = await _listener.AcceptTcpClientAsync(_stop.Token).ConfigureAwait(false);
                if (!greets)
                {
                    // Accetta e tace: il client aspetta il saluto finché non scade il tempo.
                    await Task.Delay(System.Threading.Timeout.Infinite, _stop.Token).ConfigureAwait(false);
                    return;
                }

                await using var stream = client.GetStream();
                using var reader = new StreamReader(stream, Encoding.ASCII);
                await WriteAsync(stream, "220 test ESMTP\r\n").ConfigureAwait(false);
                while (await reader.ReadLineAsync(_stop.Token).ConfigureAwait(false) is { } line)
                {
                    lock (_received)
                    {
                        _received.Add(line);
                    }

                    await WriteAsync(
                        stream,
                        line.StartsWith("EHLO", StringComparison.OrdinalIgnoreCase) ? "250 test\r\n" : "502 not implemented\r\n")
                        .ConfigureAwait(false);
                }
            }
            catch (Exception ex) when (ex is OperationCanceledException or IOException or SocketException or ObjectDisposedException)
            {
                // Il test ha finito, o il client ha chiuso la connessione.
            }
        }

        private async Task WriteAsync(Stream stream, string text)
        {
            await stream.WriteAsync(Encoding.ASCII.GetBytes(text), _stop.Token).ConfigureAwait(false);
            await stream.FlushAsync(_stop.Token).ConfigureAwait(false);
        }
    }
}
