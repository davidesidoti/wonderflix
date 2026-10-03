namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti che non sono tipi di evento (spec F §6.9). La chiave passata a
/// <see cref="RateLimiter.TryAcquire"/> è l'id dell'utente (formato "N").
/// </summary>
public static class LimitTypes
{
    /// <summary>Nuove richieste di amicizia.</summary>
    public const string FriendRequests = "FriendRequests";

    /// <summary>Ricerche di utenti.</summary>
    public const string Searches = "Searches";
}
