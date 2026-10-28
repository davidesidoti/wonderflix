using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// La chiave di un titolo da scaricare (spec T §3): <c>movie:{idRadarr}</c>, <c>episode:{idEpisodioSonarr}</c>,
/// <c>season:{idSerieSonarr}:{stagione}</c>. <c>Season</c> vale 0 per film ed episodi.
/// </summary>
public readonly record struct DownloadKey(string Kind, int Id, int Season)
{
    /// <summary>Legge una chiave; falso per testo vuoto, tipo sconosciuto, id non positivo o stagione mancante o negativa.</summary>
    public static bool TryParse(string? raw, out DownloadKey key)
    {
        key = default;
        var parts = raw?.Split(':');
        if (parts is null || !int.TryParse(parts.Length > 1 ? parts[1] : null, NumberStyles.None, CultureInfo.InvariantCulture, out var id) || id <= 0)
        {
            return false;
        }

        switch (parts[0], parts.Length)
        {
            case ("movie", 2):
                key = new DownloadKey(DownloadKinds.Movie, id, 0);
                return true;
            case ("episode", 2):
                key = new DownloadKey(DownloadKinds.Episode, id, 0);
                return true;
            case ("season", 3) when int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out var season):
                key = new DownloadKey(DownloadKinds.Season, id, season);
                return true;
            default:
                return false;
        }
    }

    /// <summary>La forma scritta, quella che <see cref="TryParse"/> rilegge.</summary>
    public override string ToString() => Kind switch
    {
        DownloadKinds.Movie => $"movie:{Id}",
        DownloadKinds.Episode => $"episode:{Id}",
        _ => $"season:{Id}:{Season}",
    };
}
