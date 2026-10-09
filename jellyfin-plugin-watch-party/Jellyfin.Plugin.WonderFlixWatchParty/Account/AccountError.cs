namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli errori dei contatti e del recupero (spec L §7.6): il nome è il Code della risposta.</summary>
public enum AccountError
{
    ChannelOff,
    RateLimited,
    InvalidTarget,
    MemberNotFound,
    DmClosed,
    SendFailed,
    InvalidCode,
    WeakPassword,
    NotAllowed,
    NoContacts,
    UnknownUser,
    Invalid,
}

/// <summary>Esito di un'operazione: un valore oppure un errore.</summary>
public sealed record AccountResult<T>(AccountError? Error, T? Value)
    where T : class
{
    public static AccountResult<T> Ok(T value) => new(null, value);

    public static AccountResult<T> Fail(AccountError error) => new(error, null);
}
