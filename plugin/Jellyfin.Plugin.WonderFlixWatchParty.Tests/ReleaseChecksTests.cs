using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseChecksTests
{
    private const long Gb = 1_000_000_000;

    private static ArrQuality Q(int id, string name) => new() { Id = id, Name = name };

    private static ArrQualityProfileItem Item(int id, string name, bool allowed = true) => new() { Allowed = allowed, Quality = Q(id, name) };

    // Dal più basso: SDTV (non ammessa), gruppo WEB 1080p (WEBDL e WEBRip), Bluray-1080p.
    private static ArrQualityProfile Profile(int minFormatScore = 0) => new()
    {
        MinFormatScore = minFormatScore,
        Items =
        [
            Item(1, "SDTV", false),
            new ArrQualityProfileItem { Allowed = true, Name = "WEB 1080p", Items = [Item(3, "WEBDL-1080p"), Item(15, "WEBRip-1080p")] },
            Item(7, "Bluray-1080p"),
        ],
    };

    private static ArrRelease Release(string title = "Show S01E01 1080p WEB-DL", int qualityId = 3, string quality = "WEBDL-1080p", double gb = 1.2, int? seeders = 10, int score = 0) => new()
    {
        Guid = "g",
        IndexerId = 5,
        Title = title,
        Size = (long)(gb * Gb),
        Seeders = seeders,
        CustomFormatScore = score,
        Quality = new ArrQualityModel { Quality = Q(qualityId, quality) },
        Source = ReleaseSource.Prowlarr,
    };

    private static ChecksContext Context(
        ArrQualityProfile? profile = null,
        IReadOnlyList<ArrQualityDefinition>? definitions = null,
        IReadOnlyList<ArrReleaseProfile>? releaseProfiles = null,
        IReadOnlyList<ArrBlocklistItem>? blocklist = null,
        IReadOnlyDictionary<int, int>? minSeeders = null,
        IReadOnlyList<int>? titleTags = null) =>
        new(profile ?? Profile(), definitions ?? [], releaseProfiles ?? [], blocklist ?? [], minSeeders ?? new Dictionary<int, int>(), titleTags ?? []);

    [Fact]
    public void AnOrdinaryReleasePasses() =>
        Assert.Null(ReleaseChecks.Check(Release(), Context(), 24));

    [Fact]
    public void ABlocklistedTitleIsBlocklistedWhateverTheCase()
    {
        var context = Context(blocklist: [new ArrBlocklistItem { SourceTitle = "SHOW s01e01 1080p web-dl", SeriesId = 1 }]);

        Assert.Equal(("Blocklisted", null), ReleaseChecks.Check(Release(), context, 24));
    }

    [Fact]
    public void ARequiredTermThatIsMissingIsRestricted()
    {
        var context = Context(releaseProfiles: [new ArrReleaseProfile { Enabled = true, Required = ["ITA"] }]);

        Assert.Equal(("Restricted", "ITA"), ReleaseChecks.Check(Release(), context, 24));
        Assert.Null(ReleaseChecks.Check(Release("Show S01E01 ita 1080p"), context, 24));
    }

    [Fact]
    public void AnIgnoredTermIsRestrictedWithThatTerm()
    {
        var context = Context(releaseProfiles: [new ArrReleaseProfile { Enabled = true, Ignored = ["cam", "WEB-DL"] }]);

        Assert.Equal(("Restricted", "WEB-DL"), ReleaseChecks.Check(Release(), context, 24));
    }

    [Fact]
    public void AReleaseProfileWithTagsOnlyCountsForTheTitleWithThoseTags()
    {
        var profile = new ArrReleaseProfile { Enabled = true, Ignored = ["WEB-DL"], Tags = [7] };

        Assert.Null(ReleaseChecks.Check(Release(), Context(releaseProfiles: [profile], titleTags: [1]), 24));
        Assert.Equal(("Restricted", "WEB-DL"), ReleaseChecks.Check(Release(), Context(releaseProfiles: [profile], titleTags: [1, 7]), 24));
        Assert.Null(ReleaseChecks.Check(Release(), Context(releaseProfiles: [new ArrReleaseProfile { Enabled = false, Ignored = ["WEB-DL"] }], titleTags: [7]), 24));
    }

    [Fact]
    public void AQualityNotAllowedInTheProfileIsNotWanted()
    {
        Assert.Equal(("NotWanted", "SDTV"), ReleaseChecks.Check(Release(qualityId: 1, quality: "SDTV"), Context(), 24));
        Assert.Equal(("NotWanted", "HDTV-720p"), ReleaseChecks.Check(Release(qualityId: 4, quality: "HDTV-720p"), Context(), 24));
    }

    [Fact]
    public void AQualityInsideAnAllowedGroupIsWanted() =>
        Assert.Null(ReleaseChecks.Check(Release(qualityId: 15, quality: "WEBRip-1080p"), Context(), 24));

    [Fact]
    public void AReleaseOutsideTheQualityWeightLimitsIsNotWanted()
    {
        // 24 min x 20 MB/min = 480 MiB (~0,50 GB); 24 x 100 = 2400 MiB (~2,5 GB).
        var definitions = new[] { new ArrQualityDefinition { Quality = Q(3, "WEBDL-1080p"), MinSize = 20, MaxSize = 100 } };

        Assert.Equal(("NotWanted", "Size"), ReleaseChecks.Check(Release(gb: 0.3), Context(definitions: definitions), 24));
        Assert.Equal(("NotWanted", "Size"), ReleaseChecks.Check(Release(gb: 3), Context(definitions: definitions), 24));
        Assert.Null(ReleaseChecks.Check(Release(gb: 1.2), Context(definitions: definitions), 24));
    }

    [Fact]
    public void AFullSeasonIsMeasuredOnTheWholeSeason()
    {
        // 20-100 MB al minuto; 48 minuti sono gli episodi mancanti, 240 la stagione intera.
        var definitions = new[] { new ArrQualityDefinition { Quality = Q(3, "WEBDL-1080p"), MinSize = 20, MaxSize = 100 } };
        ArrRelease Pack(double gb)
        {
            var pack = Release(gb: gb);
            pack.FullSeason = true;
            return pack;
        }

        Assert.Null(ReleaseChecks.Check(Pack(20), Context(definitions: definitions), 48, seasonMinutes: 240));
        Assert.Equal(("NotWanted", "Size"), ReleaseChecks.Check(Pack(30), Context(definitions: definitions), 48, seasonMinutes: 240));
        Assert.Equal(("NotWanted", "Size"), ReleaseChecks.Check(Pack(4), Context(definitions: definitions), 48, seasonMinutes: 240));

        // Senza la durata della stagione niente massimo; il minimo resta, sugli episodi mancanti.
        Assert.Null(ReleaseChecks.Check(Pack(50), Context(definitions: definitions), 48));
        Assert.Equal(("NotWanted", "Size"), ReleaseChecks.Check(Pack(0.5), Context(definitions: definitions), 48));
    }

    [Fact]
    public void ANullOrZeroMaxSizeAndAnUnknownRuntimeSkipTheSizeCheck()
    {
        var unlimited = new[] { new ArrQualityDefinition { Quality = Q(3, "WEBDL-1080p"), MinSize = 1, MaxSize = null } };
        var zero = new[] { new ArrQualityDefinition { Quality = Q(3, "WEBDL-1080p"), MinSize = 0, MaxSize = 0 } };
        var tight = new[] { new ArrQualityDefinition { Quality = Q(3, "WEBDL-1080p"), MinSize = 1000, MaxSize = 1001 } };

        Assert.Null(ReleaseChecks.Check(Release(gb: 50), Context(definitions: unlimited), 24));
        Assert.Null(ReleaseChecks.Check(Release(gb: 50), Context(definitions: zero), 24));
        Assert.Null(ReleaseChecks.Check(Release(gb: 50), Context(definitions: tight), 0));
    }

    [Fact]
    public void FewerSeedersThanTheIndexerMinimumIsNotWanted()
    {
        var context = Context(minSeeders: new Dictionary<int, int> { [5] = 3 });

        Assert.Equal(("NotWanted", "Seeders"), ReleaseChecks.Check(Release(seeders: 2), context, 24));
        Assert.Null(ReleaseChecks.Check(Release(seeders: 3), context, 24));
        Assert.Null(ReleaseChecks.Check(Release(seeders: null), context, 24));
    }

    [Fact]
    public void AScoreBelowTheProfileMinimumIsNotWanted()
    {
        var context = Context(profile: Profile(minFormatScore: 0));

        Assert.Equal(("NotWanted", "Score"), ReleaseChecks.Check(Release(score: -9980), context, 24));
        Assert.Null(ReleaseChecks.Check(Release(score: 0), context, 24));
    }

    [Fact]
    public void ChecksComeInTheDocumentedOrder()
    {
        var context = Context(
            blocklist: [new ArrBlocklistItem { SourceTitle = "Show S01E01 1080p WEB-DL" }],
            releaseProfiles: [new ArrReleaseProfile { Enabled = true, Required = ["ITA"] }]);

        Assert.Equal("Blocklisted", ReleaseChecks.Check(Release(qualityId: 1, quality: "SDTV"), context, 24)!.Value.Reason);
        Assert.Equal("Restricted", ReleaseChecks.Check(Release("Show other", qualityId: 1, quality: "SDTV"), context, 24)!.Value.Reason);
    }

    [Fact]
    public void SkipQualityIgnoresOnlyTheQualityCheck()
    {
        var seven20 = Release(qualityId: 4, quality: "HDTV-720p");
        Assert.Equal(("NotWanted", "HDTV-720p"), ReleaseChecks.Check(seven20, Context(), 24));
        Assert.Null(ReleaseChecks.Check(seven20, Context(), 24, skipQuality: true));

        var fewSeeders = Release(qualityId: 4, quality: "HDTV-720p", seeders: 1);
        var context = Context(minSeeders: new Dictionary<int, int> { [5] = 3 });
        Assert.Equal(("NotWanted", "Seeders"), ReleaseChecks.Check(fewSeeders, context, 24, skipQuality: true));
    }
}
