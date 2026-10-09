using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il codice a 6 cifre in un messaggio.</summary>
internal static class FakeCodes
{
    public static string In(string text) => Regex.Match(text, @"\b\d{6}\b").Value;
}

/// <summary>Il bot Discord finto: membri, esiti degli invii e messaggi mandati.</summary>
internal sealed class FakeDiscordSender : IDiscordSender
{
    /// <summary>Membri del server per nome utente (senza maiuscole).</summary>
    public Dictionary<string, DiscordMember> Members { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Se true, la ricerca dei membri dà errore.</summary>
    public bool SearchFails { get; set; }

    /// <summary>Esito degli invii per id Discord; di default Sent.</summary>
    public Dictionary<string, SendOutcome> Outcomes { get; } = [];

    public DiscordCheck Check { get; set; } = DiscordCheck.Ok;

    /// <summary>I messaggi arrivati, in ordine.</summary>
    public List<(string UserId, string Text)> Sent { get; } = [];

    /// <summary>I nomi cercati, in ordine.</summary>
    public List<string> Searches { get; } = [];

    public Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken)
    {
        Searches.Add(username);
        return Task.FromResult(
            SearchFails ? DiscordLookup.Error
            : Members.TryGetValue(username, out var member) ? DiscordLookup.Found(member)
            : DiscordLookup.NotFound);
    }

    public Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken)
    {
        var outcome = Outcomes.GetValueOrDefault(userId, SendOutcome.Sent);
        if (outcome == SendOutcome.Sent)
        {
            Sent.Add((userId, text));
        }

        return Task.FromResult(outcome);
    }

    public Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken) => Task.FromResult(Check);

    /// <summary>L'ultimo codice mandato a questo id.</summary>
    public string LastCode(string userId) => FakeCodes.In(Sent.Last(s => s.UserId == userId).Text);
}

/// <summary>La password attuale finta: ogni utente ha "giusta", se il test non gli dà un'altra password (anche vuota).</summary>
internal sealed class FakePasswordCheck : IPasswordCheck
{
    /// <summary>Password per utente.</summary>
    public Dictionary<Guid, string> Passwords { get; } = [];

    /// <summary>I controlli fatti, in ordine.</summary>
    public List<(Guid UserId, string Password)> Calls { get; } = [];

    public Task<bool> IsCurrentPasswordAsync(Guid userId, string password)
    {
        Calls.Add((userId, password));
        return Task.FromResult(Passwords.GetValueOrDefault(userId, "giusta") == password);
    }
}

/// <summary>Le email finte: esiti per indirizzo e messaggi mandati.</summary>
internal sealed class FakeMailSender : IMailSender
{
    /// <summary>Esito degli invii per indirizzo (senza maiuscole); di default Sent.</summary>
    public Dictionary<string, SendOutcome> Outcomes { get; } = new(StringComparer.OrdinalIgnoreCase);

    public List<(string To, AccountMessage Message)> Sent { get; } = [];

    public Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken)
    {
        var outcome = Outcomes.GetValueOrDefault(to, SendOutcome.Sent);
        if (outcome == SendOutcome.Sent)
        {
            Sent.Add((to, message));
        }

        return Task.FromResult(outcome);
    }

    /// <summary>L'ultimo codice mandato a questo indirizzo.</summary>
    public string LastCode(string to) =>
        FakeCodes.In(Sent.Last(s => string.Equals(s.To, to, StringComparison.OrdinalIgnoreCase)).Message.Text);
}

/// <summary>Il cambio di password finto: registra le chiamate, o lancia Error.</summary>
internal sealed class FakePasswordReset : IPasswordReset
{
    public List<(Guid UserId, string Password)> Calls { get; } = [];

    public Exception? Error { get; set; }

    public Task ResetAsync(Guid userId, string newPassword)
    {
        if (Error is not null)
        {
            throw Error;
        }

        Calls.Add((userId, newPassword));
        return Task.CompletedTask;
    }
}
