using System.Net;
using System.Net.Mail;
using System.Text;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Il server SMTP letto dalla configurazione al momento dell'invio. Interno, e
/// <see cref="ToString"/> non scrive la password: così non finisce per sbaglio in un registro.
/// </summary>
internal sealed record SmtpServer(string Host, int Port, string User, string Password)
{
    public override string ToString() => $"SmtpServer {{ Host = {Host}, Port = {Port}, User = {User} }}";
}

/// <summary>
/// Le email dei codici con System.Net.Mail (spec L §7.3): STARTTLS
/// (EnableSsl), solo testo, mittente "WonderFlix". Nel registro il server
/// e l'errore, mai la password e mai un indirizzo.
/// </summary>
public sealed class SmtpMailSender(IAccountSettings settings, ILogger<SmtpMailSender> logger) : IMailSender
{
    /// <summary>Il nome del mittente.</summary>
    public const string FromName = "WonderFlix";

    /// <summary>Attesa massima di un invio.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(15);

    /// <summary>La porta del TLS implicito (SMTPS), che System.Net.Mail non sa usare.</summary>
    private const int ImplicitTlsPort = 465;

    // In coda ai messaggi d'errore sulla porta 465: lì il server aspetta il TLS subito e il nostro STARTTLS non parte.
    private const string ImplicitTlsHint = " — la porta 465 (TLS implicito) non è supportata: usa la 587 con STARTTLS";

    // Gli indirizzi nei messaggi del server SMTP ("<mario@example.com> unknown").
    private static readonly Regex Address = new(@"[^\s<>""']+@[^\s<>""']+", RegexOptions.CultureInvariant);

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    /// <summary>Chi spedisce davvero; i test lo sostituiscono.</summary>
    internal Func<SmtpServer, MailMessage, CancellationToken, Task> Transport { get; init; } = SendWithSmtpAsync;

    public async Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsEmailConfigured())
        {
            return SendOutcome.Failed;
        }

        var server = new SmtpServer(settings.SmtpHost, settings.SmtpPort, settings.SmtpUser, settings.SmtpPassword);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var mail = new MailMessage(new MailAddress(settings.MailFrom, FromName), new MailAddress(to))
            {
                Subject = message.Subject,
                Body = message.Text,
                IsBodyHtml = false,
                SubjectEncoding = Encoding.UTF8,
                BodyEncoding = Encoding.UTF8,
            };
            await Transport(server, mail, timeout.Token).ConfigureAwait(false);
            return SendOutcome.Sent;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(
                "Email non inviata: nessuna risposta da {Host}:{Port} in {Timeout}{Hint}", server.Host, server.Port, Timeout, Hint(server));
            return SendOutcome.Failed;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Qualunque errore del trasporto è un esito: esce solo l'annullamento di chi chiama.
            // Si scrive anche la causa originale (di solito la rete), sempre senza indirizzi.
            var root = ex.GetBaseException();
            var cause = ReferenceEquals(root, ex) ? string.Empty : $" (causa: {root.GetType().Name} {Redact(root.Message)})";
            logger.LogWarning(
                "Email non inviata tramite {Host}:{Port}: {Error} {Message}{Cause}{Hint}",
                server.Host,
                server.Port,
                ex.GetType().Name,
                Redact(ex.Message),
                cause,
                Hint(server));
            return SendOutcome.Failed;
        }
    }

    private static string Hint(SmtpServer server) => server.Port == ImplicitTlsPort ? ImplicitTlsHint : string.Empty;

    private static string Redact(string? text) => text is null ? string.Empty : Address.Replace(text, "[email]");

    private static async Task SendWithSmtpAsync(SmtpServer server, MailMessage mail, CancellationToken cancellationToken)
    {
        using var client = new SmtpClient(server.Host, server.Port)
        {
            EnableSsl = true,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Credentials = new NetworkCredential(server.User, server.Password),
        };
        await client.SendMailAsync(mail, cancellationToken).ConfigureAwait(false);
    }
}
