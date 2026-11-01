namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>La fase della ricerca di una voce nella panoramica: in coda per il prossimo giro, o cercata adesso.</summary>
public static class DownloadSearchPhases
{
    public const string Queued = "Queued";

    public const string Searching = "Searching";
}
