using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class DownloadRuleTests
{
    private const long Gb = 1_000_000_000;

    private static readonly IReadOnlyDictionary<int, int> NoPriority = new Dictionary<int, int>();

    private static RuleInput Input(int minutes = 106, int minScore = 50, bool movie = true, IReadOnlyDictionary<int, int>? priority = null) =>
        new(minutes, movie, DownloadRule.DefaultMinGbPerHour, minScore, priority ?? NoPriority);

    private static ArrRelease Release(string guid, string quality, int resolution, double gb, int score, int? seeders = 10, int indexerId = 1, params string[] rejections) => new()
    {
        Guid = guid,
        IndexerId = indexerId,
        Indexer = "idx" + indexerId,
        Title = "t-" + guid,
        Size = (long)(gb * Gb),
        Seeders = seeders,
        Quality = new ArrQualityModel { Quality = new ArrQuality { Id = QualityId(quality), Name = quality, Resolution = resolution } },
        CustomFormatScore = score,
        Rejected = rejections.Length > 0,
        Rejections = rejections.ToList(),
    };

    private static int QualityId(string name) => name switch
    {
        "HDTV-720p" => 4,
        "WEBDL-720p" => 5,
        "WEBRip-720p" => 14,
        "Bluray-720p" => 6,
        "HDTV-1080p" => 9,
        "WEBDL-1080p" => 3,
        "WEBRip-1080p" => 15,
        "Bluray-1080p" => 7,
        _ => 99,
    };

    private static ArrQualityProfileItem Single(string name) => new() { Allowed = true, Quality = new ArrQuality { Id = QualityId(name), Name = name } };

    private static ArrQualityProfileItem Group(string name, params string[] members) => new()
    {
        Allowed = true,
        Name = name,
        Items = members.Select(Single).ToList(),
    };

    // Il profilo Main di Radarr: dal più basso al più alto, con una qualità non ammessa in mezzo.
    private static ArrQualityProfile MainProfile() => new()
    {
        Items =
        [
            Single("HDTV-720p"),
            Group("WEB 720p", "WEBDL-720p", "WEBRip-720p"),
            new ArrQualityProfileItem { Allowed = false, Quality = new ArrQuality { Id = 1, Name = "SDTV" } },
            Single("Bluray-720p"),
            Single("HDTV-1080p"),
            Group("WEB 1080p", "WEBDL-1080p", "WEBRip-1080p"),
            Single("Bluray-1080p"),
        ],
    };

    // Lo stesso profilo con WEB 1080p e Bluray-1080p nello stesso gruppo.
    private static ArrQualityProfile MergedProfile() => new()
    {
        Items =
        [
            Single("HDTV-1080p"),
            Group("1080p", "WEBDL-1080p", "WEBRip-1080p", "Bluray-1080p"),
        ],
    };

    [Fact]
    public void TheLightestTopScoreWins()
    {
        var result = DownloadRule.Choose(
            [
                Release("a", "WEBDL-1080p", 1080, 2.9, 150),
                Release("b", "WEBRip-1080p", 1080, 1.89, 150),
                Release("c", "WEBRip-1080p", 1080, 4.83, 150),
            ],
            Input());

        Assert.Equal("b", result.Choice!.Guid);
        Assert.Equal(["b", "a", "c"], result.Candidates.Select(r => r.Guid));
        Assert.False(result.BelowMinScore);
    }

    [Fact]
    public void ScoreComesBeforeWeight()
    {
        var result = DownloadRule.Choose(
            [
                Release("light", "WEBRip-1080p", 1080, 1.2, 50),
                Release("heavy", "Bluray-1080p", 1080, 9.71, 150),
            ],
            Input());

        Assert.Equal("heavy", result.Choice!.Guid);
    }

    [Fact]
    public void TenEightyBeatsSevenTwentyAtTheSameScore()
    {
        var result = DownloadRule.Choose(
            [
                Release("720", "Bluray-720p", 720, 8.38, 150),
                Release("1080", "Bluray-1080p", 1080, 9.47, 150),
            ],
            Input(minutes: 155));

        Assert.Equal("1080", result.Choice!.Guid);
    }

    [Fact]
    public void ExistingFileRejectionsAreIgnored()
    {
        var result = DownloadRule.Choose(
            [
                Release("ok", "WEBRip-1080p", 1080, 1.89, 150, 10, 1, "Existing file on disk has a equal or higher Custom Format score: 150"),
                Release("no", "WEBDL-1080p", 1080, 2.9, 150, 10, 1, "WEBDL-1080p is not wanted in profile"),
            ],
            Input());

        Assert.Equal(["ok"], result.Candidates.Select(r => r.Guid));
        var rejected = Assert.Single(result.Rejected);
        Assert.Equal("no", rejected.Release.Guid);
        Assert.Equal("Arr", rejected.Reason);
        Assert.Equal("WEBDL-1080p is not wanted in profile", rejected.Detail);
    }

    [Fact]
    public void TheOtherIgnoredPrefixesAreIgnoredWhateverTheCase()
    {
        var result = DownloadRule.Choose(
            [
                Release("a", "WEBRip-1080p", 1080, 1.5, 150, 10, 1, "Not an upgrade for existing movie file"),
                Release("b", "WEBRip-1080p", 1080, 1.6, 150, 10, 1, "release in queue already"),
            ],
            Input());

        Assert.Equal(2, result.Candidates.Count);
        Assert.Empty(result.Rejected);
    }

    [Fact]
    public void AnIgnoredTextDoesNotHideARealRejection()
    {
        var result = DownloadRule.Choose(
            [Release("a", "WEBRip-1080p", 1080, 1.5, 150, 10, 1, "Not an upgrade for existing movie file", "Unknown movie")],
            Input());

        Assert.Empty(result.Candidates);
        Assert.Equal("Unknown movie", Assert.Single(result.Rejected).Detail);
    }

    [Fact]
    public void NullReleasesAndReleasesWithoutGuidAreDropped()
    {
        var result = DownloadRule.Choose(
            [null, Release("", "WEBRip-1080p", 1080, 1.5, 150), Release("ok", "WEBRip-1080p", 1080, 1.5, 150)],
            Input());

        Assert.Equal(["ok"], result.Candidates.Select(r => r.Guid));
        Assert.Empty(result.Rejected);
    }

    [Fact]
    public void TooSmallReleasesAreRejected()
    {
        var result = DownloadRule.Choose(
            [
                Release("small", "WEBRip-1080p", 1080, 1.0, 150),
                Release("ok", "WEBRip-1080p", 1080, 1.5, 150),
            ],
            Input());

        var rejected = Assert.Single(result.Rejected);
        Assert.Equal("small", rejected.Release.Guid);
        Assert.Equal("TooSmall", rejected.Reason);
        Assert.Equal("0.57", rejected.Detail);
        Assert.Equal(["ok"], result.Candidates.Select(r => r.Guid));
    }

    [Fact]
    public void RuntimeFallsBackWhenMissing()
    {
        // Su 100 minuti: 1,3 GB sono 0,78 GB all'ora (scartata), 1,4 GB sono 0,84 (passa).
        var small = DownloadRule.Choose([Release("a", "WEBRip-1080p", 1080, 1.3, 150)], Input(minutes: 0));
        Assert.Equal("0.78", Assert.Single(small.Rejected).Detail);

        var ok = DownloadRule.Choose([Release("a", "WEBRip-1080p", 1080, 1.4, 150)], Input(minutes: 0));
        Assert.Equal("a", ok.Choice!.Guid);
    }

    [Fact]
    public void AnEpisodeFallsBackToFortyMinutes()
    {
        // Su 40 minuti: 0,5 GB sono 0,75 GB all'ora (scartata), 0,6 GB sono 0,9 (passa).
        var result = DownloadRule.Choose(
            [
                Release("a", "WEBRip-1080p", 1080, 0.5, 150),
                Release("b", "WEBRip-1080p", 1080, 0.6, 150),
            ],
            Input(minutes: 0, movie: false));

        Assert.Equal(["b"], result.Candidates.Select(r => r.Guid));
    }

    [Fact]
    public void BelowMinScoreHasNoChoice()
    {
        var result = DownloadRule.Choose([Release("a", "WEBRip-1080p", 1080, 1.5, 0)], Input(minScore: 50));

        Assert.Null(result.Choice);
        Assert.True(result.BelowMinScore);
        Assert.Single(result.Candidates);
    }

    [Fact]
    public void NoCandidatesIsNotBelowMinScore()
    {
        var result = DownloadRule.Choose([], Input());

        Assert.Null(result.Choice);
        Assert.False(result.BelowMinScore);
    }

    [Fact]
    public void TheSameFileOnTwoIndexersPrefersSeedersThenPriority()
    {
        var bySeeders = DownloadRule.Choose(
            [
                Release("few", "WEBRip-1080p", 1080, 1.5, 150, 5, 1),
                Release("many", "WEBRip-1080p", 1080, 1.5, 150, 11, 2),
            ],
            Input());
        Assert.Equal("many", bySeeders.Choice!.Guid);

        var byPriority = DownloadRule.Choose(
            [
                Release("p25", "WEBRip-1080p", 1080, 1.5, 150, 8, 1),
                Release("p20", "WEBRip-1080p", 1080, 1.5, 150, 8, 2),
            ],
            Input(priority: new Dictionary<int, int> { [1] = 25, [2] = 20 }));
        Assert.Equal("p20", byPriority.Choice!.Guid);
    }

    [Fact]
    public void NullSeedersCountAsZeroAndAnUnknownIndexerIsTwentyFive()
    {
        var seeders = DownloadRule.Choose(
            [
                Release("usenet", "WEBRip-1080p", 1080, 1.5, 150, null, 1),
                Release("torrent", "WEBRip-1080p", 1080, 1.5, 150, 1, 2),
            ],
            Input());
        Assert.Equal("torrent", seeders.Choice!.Guid);

        // L'indexer 1 non è elencato (25): sta tra quello con priorità 10 e quello con 30.
        var priority = new Dictionary<int, int> { [2] = 10, [3] = 30 };
        var result = DownloadRule.Choose(
            [
                Release("unknown", "WEBRip-1080p", 1080, 1.5, 150, 5, 1),
                Release("late", "WEBRip-1080p", 1080, 1.5, 150, 5, 3),
                Release("early", "WEBRip-1080p", 1080, 1.5, 150, 5, 2),
            ],
            Input(priority: priority));
        Assert.Equal(["early", "unknown", "late"], result.Candidates.Select(r => r.Guid));
    }

    [Fact]
    public void TheOrderIsStableWhateverTheInputOrder()
    {
        var a = Release("a", "WEBRip-1080p", 1080, 1.5, 150, 5, 1);
        var b = Release("b", "WEBRip-1080p", 1080, 1.5, 150, 5, 1);

        Assert.Equal(["a", "b"], DownloadRule.Choose([a, b], Input()).Candidates.Select(r => r.Guid));
        Assert.Equal(["a", "b"], DownloadRule.Choose([b, a], Input()).Candidates.Select(r => r.Guid));
    }

    [Fact]
    public void WouldImportFollowsTheProfileOrder()
    {
        var main = MainProfile();

        Assert.False(DownloadRule.WouldImport(main, 15, 150, 7, 0));      // WEBRip-1080p su Bluray-1080p
        Assert.True(DownloadRule.WouldImport(main, 7, 0, 15, 150));       // Bluray su WEBRip
        Assert.False(DownloadRule.WouldImport(main, 4, 150, 9, 50));      // 720p su 1080p
        Assert.True(DownloadRule.WouldImport(main, 15, 150, null, null)); // nessun file
    }

    [Fact]
    public void WouldImportTreatsAGroupAsOnePosition()
    {
        var merged = MergedProfile();

        Assert.True(DownloadRule.WouldImport(merged, 15, 150, 7, 0));    // stesso gruppo, punteggio più alto
        Assert.False(DownloadRule.WouldImport(merged, 15, 150, 7, 150)); // stesso gruppo, stesso punteggio
        Assert.False(DownloadRule.WouldImport(merged, 15, 100, 7, 150)); // stesso gruppo, punteggio più basso
        Assert.False(DownloadRule.WouldImport(merged, 9, 150, 7, 50));   // HDTV-1080p sta sotto al gruppo

        Assert.True(DownloadRule.WouldImport(MainProfile(), 15, 150, 3, 50)); // WEBRip su WEBDL: stesso gruppo
    }

    [Fact]
    public void WouldImportEdgeCases()
    {
        var main = MainProfile();

        Assert.False(DownloadRule.WouldImport(main, 1, 150, 7, 0));        // SDTV non ammessa
        Assert.False(DownloadRule.WouldImport(main, 99, 150, null, null)); // qualità nuova fuori dal profilo, anche senza file
        Assert.True(DownloadRule.WouldImport(main, 4, 0, 99, 0));          // file attuale fuori dal profilo: posizione -1
    }

    [Fact]
    public void GbPerHourUsesDecimalGigabytes()
    {
        Assert.Equal(1.0, DownloadRule.GbPerHour(Gb, 60), 5);
        Assert.Equal(0.0, DownloadRule.GbPerHour(Gb, 0), 5);
    }
}
