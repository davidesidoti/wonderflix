using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Le impostazioni dello spazio con i valori iniziali (spec U §10), modificabili dai test.</summary>
internal sealed class FakeSpaceSettings : ISpaceSettings
{
    public string QbitUrl { get; set; } = "";

    public string QbitUser { get; set; } = "";

    public string QbitPassword { get; set; } = "";

    public int StaleMonths { get; set; } = 6;

    public int RequestGraceDays { get; set; } = 60;

    public int LowRating { get; set; } = 2;

    public int HighRating { get; set; } = 4;

    public int MinRatings { get; set; } = 2;

    public double HeavyGbPerHour { get; set; } = 4.0;

    public SeedSettings Seed { get; set; } = new(["itatorrents.xyz", "shareisland.org"], 10.0, 30);

    public IReadOnlyList<string> ScanFolders { get; set; } = ["/srv/downloads", "/srv/seedings"];

    public string QuotaFile { get; set; } = "";
}
