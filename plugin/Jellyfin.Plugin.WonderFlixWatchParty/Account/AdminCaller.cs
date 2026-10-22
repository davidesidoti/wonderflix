namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Chi ha chiamato una funzione dell'admin, scritto nel registro.</summary>
internal static class AdminCaller
{
    /// <summary>
    /// L'id dell'admin in formato "N". Con una chiave API non c'è un utente
    /// (l'id è tutto a zero): si scrive "chiave API".
    /// </summary>
    public static string Describe(Guid adminId) => adminId == Guid.Empty ? "chiave API" : adminId.ToString("N");
}
