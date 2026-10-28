using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Impostazioni dei download da cambiare nel test; senza una soglia scritta vale la decisione 8.</summary>
internal sealed class FakeDownloadSettings : IDownloadSettings
{
    public bool Enabled { get; set; } = true;

    public double MinGbPerHour { get; set; } = DownloadDefaults.MinGbPerHour;

    public Dictionary<(ArrKind Kind, int ProfileId), ProfileThresholds> Thresholds { get; } = [];

    public ProfileThresholds For(ArrKind kind, int profileId, string? profileName) =>
        Thresholds.TryGetValue((kind, profileId), out var t) ? t : DownloadDefaults.For(profileName);
}
