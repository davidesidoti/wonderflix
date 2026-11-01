namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Lo stato della ricerca dell'admin in background (spec W §4.4): in corso, finita con il risultato (o l'errore), titolo che
/// Radarr/Sonarr non hanno, o nessuna ricerca (mai fatta o più vecchia di <see cref="DownloadService.SearchResultLifetime"/>).
/// </summary>
public static class DownloadSearchStates
{
    public const string Running = "Running";

    public const string Done = "Done";

    public const string Missing = "Missing";

    public const string None = "None";
}
