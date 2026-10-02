namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Costanti del protocollo con l'app (spec E §6.3).</summary>
public static class WatchPartyProtocol
{
    /// <summary>Versione del protocollo: l'app la confronta con la sua.</summary>
    public const int Version = 1;

    /// <summary>
    /// Chiave degli Arguments del GeneralCommand SendString con cui gli
    /// eventi arrivano ai client. Non è "String", che jellyfin-web
    /// scriverebbe nel campo con il focus.
    /// </summary>
    public const string ArgumentKey = "WonderFlixWatchParty";

    /// <summary>Lunghezza massima di un messaggio, in punti di codice (come nell'app).</summary>
    public const int MaxChatLength = 200;
}
