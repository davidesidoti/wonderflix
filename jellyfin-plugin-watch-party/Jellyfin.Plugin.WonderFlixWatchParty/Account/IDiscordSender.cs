namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Esito di un invio (spec L §7.3).</summary>
public enum SendOutcome
{
    Sent,

    /// <summary>Discord: l'utente non accetta messaggi diretti dal bot.</summary>
    DmClosed,

    Failed,
}

/// <summary>Un membro del server Discord.</summary>
public sealed record DiscordMember(string Id, string Username);

/// <summary>Esito della ricerca di un membro: trovato, non trovato, oppure errore di Discord.</summary>
public sealed record DiscordLookup(DiscordMember? Member, bool Failed)
{
    public static readonly DiscordLookup NotFound = new(null, false);

    public static readonly DiscordLookup Error = new(null, true);

    public static DiscordLookup Found(DiscordMember member) => new(member, false);
}

/// <summary>Esito del controllo di token e server.</summary>
public enum DiscordCheck
{
    Ok,

    /// <summary>Discord ha rifiutato il token, o il bot non è nel server.</summary>
    Invalid,

    /// <summary>Discord non ha risposto, o ha risposto con un altro errore.</summary>
    Failed,
}

/// <summary>Il bot Discord dei codici (spec L §7.3). Non lancia: gli errori sono esiti.</summary>
public interface IDiscordSender
{
    /// <summary>Il membro del server con esattamente questo nome utente (senza badare alle maiuscole).</summary>
    Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken);

    /// <summary>Un messaggio diretto all'utente Discord con questo id.</summary>
    Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken);

    /// <summary>Token e server validi.</summary>
    Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken);
}
