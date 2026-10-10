using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Sonarr e Radarr configurati, da cambiare nel test.</summary>
internal sealed class FakeArrSettings : IArrSettings
{
    public ArrEndpoint Sonarr { get; set; } = new("https://arr.example/sonarr", "sonarr-key");

    public ArrEndpoint Radarr { get; set; } = new("https://arr.example/radarr", "radarr-key");

    public int SeriesDays { get; set; } = ArrLimits.DefaultSeriesDays;

    public int MovieDays { get; set; } = ArrLimits.DefaultMovieDays;
}
