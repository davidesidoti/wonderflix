using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// L'API REST di Discord per il bot dei codici (spec L §7.3): cerca un
/// membro del server, manda un messaggio diretto, controlla token e
/// server. Nel registro solo metodo, percorso senza query ed esito: mai il
/// token, mai il testo.
/// </summary>
public sealed class DiscordBotClient(
    IHttpClientFactory httpClientFactory,
    IAccountSettings settings,
    ILogger<DiscordBotClient> logger) : IDiscordSender
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixDiscord";

    /// <summary>L'API v10 di Discord.</summary>
    public const string ApiBase = "https://discord.com/api/v10/";

    /// <summary>Codice d'errore di Discord: l'utente non accetta messaggi diretti dal bot.</summary>
    public const int CannotMessageUser = 50007;

    /// <summary>Risultati della ricerca: Discord non dice in che ordine dà i risultati della ricerca per prefisso.</summary>
    public const int SearchLimit = 100;

    /// <summary>
    /// Attesa massima di un'operazione intera (ricerca, messaggio diretto con i
    /// suoi due passi, controllo): l'app aspetta al massimo 30 s una risposta del server.
    /// </summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(8);

    // Discord vuole un User-Agent "DiscordBot (url, versione)".
    private static readonly string UserAgent =
        $"DiscordBot (https://github.com/davidesidoti/wonderflix, {typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0"})";

    /// <summary>Attesa massima di un'operazione intera; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public async Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return DiscordLookup.Error;
        }

        using var budget = StartBudget(cancellationToken);
        var reply = await SendAsync(
            HttpMethod.Get,
            $"guilds/{settings.DiscordGuildId}/members/search?query={Uri.EscapeDataString(username)}&limit={SearchLimit}",
            null,
            budget.Token,
            cancellationToken).ConfigureAwait(false);
        if (reply is not { Status: 200 })
        {
            return DiscordLookup.Error;
        }

        try
        {
            using var json = JsonDocument.Parse(reply.Body);
            foreach (var member in json.RootElement.EnumerateArray())
            {
                // I bot del server non sono persone da collegare: un bot con lo stesso nome non deve nascondere l'utente vero.
                if (member.TryGetProperty("user", out var user)
                    && !(user.TryGetProperty("bot", out var bot) && bot.ValueKind == JsonValueKind.True)
                    && user.TryGetProperty("id", out var id)
                    && user.TryGetProperty("username", out var name)
                    && name.GetString() is { } found
                    && string.Equals(found, username, StringComparison.OrdinalIgnoreCase)
                    && id.GetString() is { } memberId
                    && DiscordIds.IsSnowflake(memberId))
                {
                    return DiscordLookup.Found(new DiscordMember(memberId, found));
                }
            }

            return DiscordLookup.NotFound;
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            logger.LogWarning("Discord: risposta della ricerca dei membri non valida ({Error})", ex.GetType().Name);
            return DiscordLookup.Error;
        }
    }

    public async Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured() || !DiscordIds.IsSnowflake(userId))
        {
            return SendOutcome.Failed;
        }

        // Un solo limite di tempo per i due passi (apri il canale, scrivi).
        using var budget = StartBudget(cancellationToken);
        var channel = await SendAsync(
            HttpMethod.Post, "users/@me/channels", new { recipient_id = userId }, budget.Token, cancellationToken)
            .ConfigureAwait(false);
        if (channel is not { Status: 200 })
        {
            return Outcome(channel);
        }

        var channelId = ReadString(channel.Body, "id");
        if (!DiscordIds.IsSnowflake(channelId))
        {
            logger.LogWarning("Discord: il canale del messaggio diretto non ha un id valido");
            return SendOutcome.Failed;
        }

        var message = await SendAsync(
            HttpMethod.Post, $"channels/{channelId}/messages", new { content = text }, budget.Token, cancellationToken)
            .ConfigureAwait(false);
        return message is { Status: 200 } ? SendOutcome.Sent : Outcome(message);
    }

    public async Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return DiscordCheck.Invalid;
        }

        using var budget = StartBudget(cancellationToken);
        var me = await SendAsync(HttpMethod.Get, "users/@me", null, budget.Token, cancellationToken).ConfigureAwait(false);
        if (me is null)
        {
            return DiscordCheck.Failed;
        }

        if (me.Status is 401 or 403)
        {
            return DiscordCheck.Invalid;
        }

        if (me.Status != 200)
        {
            return DiscordCheck.Failed;
        }

        var guild = await SendAsync(HttpMethod.Get, $"guilds/{settings.DiscordGuildId}", null, budget.Token, cancellationToken)
            .ConfigureAwait(false);
        if (guild is null)
        {
            return DiscordCheck.Failed;
        }

        if (guild.Status is 401 or 403 or 404)
        {
            return DiscordCheck.Invalid;
        }

        if (guild.Status != 200)
        {
            return DiscordCheck.Failed;
        }

        // Senza l'intent "Server Members" o senza accesso la ricerca dei membri non funziona,
        // e il collegamento fallirebbe per tutti: meglio scoprirlo qui.
        var search = await SendAsync(
            HttpMethod.Get, $"guilds/{settings.DiscordGuildId}/members/search?query=a&limit=1", null, budget.Token, cancellationToken)
            .ConfigureAwait(false);
        return search switch
        {
            null => DiscordCheck.Failed,
            { Status: 200 } => DiscordCheck.Ok,
            { Status: 401 or 403 } => DiscordCheck.Invalid,
            _ => DiscordCheck.Failed,
        };
    }

    /// <summary>
    /// Il tempo di un'operazione intera: scade dopo <see cref="Timeout"/> e si
    /// annulla anche se si annulla chi chiama.
    /// </summary>
    private CancellationTokenSource StartBudget(CancellationToken cancellationToken)
    {
        var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(Timeout);
        return budget;
    }

    // 403 con il codice 50007: messaggi diretti chiusi. Ogni altro errore (429 compreso): Failed.
    private static SendOutcome Outcome(Reply? reply) =>
        reply is { Status: 403 } && ReadCode(reply.Body) == CannotMessageUser ? SendOutcome.DmClosed : SendOutcome.Failed;

    private static int? ReadCode(string body)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            return json.RootElement.ValueKind == JsonValueKind.Object
                && json.RootElement.TryGetProperty("code", out var code)
                && code.TryGetInt32(out var value)
                ? value
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? ReadString(string body, string property)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            return json.RootElement.ValueKind == JsonValueKind.Object
                && json.RootElement.TryGetProperty(property, out var value)
                && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>
    /// La risposta, o null se Discord non ha risposto (rete, tempo scaduto).
    /// <paramref name="budget"/> è il tempo dell'operazione (scade o segue chi
    /// chiama); <paramref name="cancellationToken"/> è quello di chi chiama, per
    /// distinguere il tempo scaduto dall'annullamento, che esce come eccezione.
    /// </summary>
    private async Task<Reply?> SendAsync(
        HttpMethod method, string path, object? body, CancellationToken budget, CancellationToken cancellationToken)
    {
        var logPath = path.Split('?')[0];
        try
        {
            using var request = new HttpRequestMessage(method, ApiBase + path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bot", settings.DiscordBotToken);
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            if (body is not null)
            {
                request.Content = JsonContent.Create(body, body.GetType());
            }

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, budget)
                .ConfigureAwait(false);
            var text = await response.Content.ReadAsStringAsync(budget).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                // Lo stato e il codice d'errore di Discord, mai il testo del messaggio.
                if (ReadCode(text) is { } code)
                {
                    logger.LogInformation("Discord {Method} {Path}: {Status} (codice {Code})", method, logPath, (int)response.StatusCode, code);
                }
                else
                {
                    logger.LogInformation("Discord {Method} {Path}: {Status}", method, logPath, (int)response.StatusCode);
                }
            }

            return new Reply((int)response.StatusCode, text);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Discord {Method} {Path}: nessuna risposta in {Timeout}", method, logPath, Timeout);
            return null;
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or FormatException or NotSupportedException)
        {
            // Questi messaggi non contengono né il token né la query.
            logger.LogWarning("Discord {Method} {Path} non riuscita: {Error} {Message}", method, logPath, ex.GetType().Name, ex.Message);
            return null;
        }
    }

    private sealed record Reply(int Status, string Body);
}
