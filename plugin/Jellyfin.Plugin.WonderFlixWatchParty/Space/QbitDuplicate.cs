namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Legge il messaggio con cui qBittorrent segnala un torrent aggiunto due volte.</summary>
public static class QbitDuplicate
{
    private const string Start = "Detected an attempt to add a duplicate torrent.";
    private const string Before = "Existing torrent: ";
    private const string After = ". Result: ";

    /// <summary>
    /// Il nome del torrent già presente, o null se il messaggio è un altro o non ha i due delimitatori. Il nome può
    /// contenere punti e parentesi: si prende fino all'ultimo ". Result: ".
    /// </summary>
    public static string? NameOf(string? message)
    {
        if (message is null || !message.StartsWith(Start, StringComparison.Ordinal))
        {
            return null;
        }

        var from = message.IndexOf(Before, Start.Length, StringComparison.Ordinal);
        var to = message.LastIndexOf(After, StringComparison.Ordinal);
        if (from < 0 || to < from + Before.Length)
        {
            return null;
        }

        var name = message[(from + Before.Length)..to];
        return name.Length == 0 ? null : name;
    }
}
