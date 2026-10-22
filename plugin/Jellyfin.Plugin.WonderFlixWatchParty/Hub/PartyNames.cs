namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Il nome che l'app dà ai gruppi SyncPlay: "Host · Titolo".</summary>
public static class PartyNames
{
    /// <summary>Tra host e titolo.</summary>
    public const string Separator = " · ";

    /// <summary>Il titolo da "Host · Titolo"; il nome intero se non ha quella forma.</summary>
    public static string TitleOf(string name)
    {
        var separator = name.IndexOf(Separator, StringComparison.Ordinal);
        return separator < 0 ? name : name[(separator + Separator.Length)..];
    }
}
