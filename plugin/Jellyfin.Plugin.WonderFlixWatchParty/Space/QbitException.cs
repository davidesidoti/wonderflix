namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Perché una chiamata a qBittorrent non è riuscita (spec U §7.2).</summary>
public enum QbitError
{
    /// <summary>Indirizzo mancante nella configurazione.</summary>
    NotConfigured,

    /// <summary>Utente o password rifiutati (login <c>Fails.</c>, 403 anche dopo un nuovo login, nessun cookie).</summary>
    Unauthorized,

    /// <summary>Irraggiungibile, lento, 5xx o risposta inattesa.</summary>
    Unreachable,

    /// <summary>404: il torrent non c'è (più).</summary>
    NotFound,
}

/// <summary>Errore di qBittorrent già classificato. Il messaggio non contiene mai password, cookie o nomi.</summary>
public sealed class QbitException(QbitError error, Exception? inner = null)
    : Exception("qBittorrent: " + error, inner)
{
    public QbitError Error { get; } = error;
}
