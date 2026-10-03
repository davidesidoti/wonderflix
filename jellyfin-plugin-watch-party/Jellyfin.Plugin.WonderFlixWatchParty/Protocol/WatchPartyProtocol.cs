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

    /// <summary>Nome del client delle app WonderFlix nelle sessioni di Jellyfin.</summary>
    public const string ClientName = "WonderFlix";

    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7). Il
    /// protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends"];
}
