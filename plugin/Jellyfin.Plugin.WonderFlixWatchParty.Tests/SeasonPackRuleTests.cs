using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeasonPackRuleTests
{
    private const long Gb = 1_000_000_000;

    private static readonly int[] Missing = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    private static readonly RuleInput PerEpisode = new(45, false, DownloadRule.DefaultMinGbPerHour, 50, new Dictionary<int, int>());

    private static ArrRelease Pack(double gb, params string[] rejections) => new()
    {
        Guid = "pack",
        Size = (long)(gb * Gb),
        CustomFormatScore = 100,
        FullSeason = true,
        Rejections = rejections.ToList(),
    };

    private static ArrRelease Single(int episode, double gb = 1) => new()
    {
        Guid = "ep" + episode,
        Size = (long)(gb * Gb),
        CustomFormatScore = 100,
        EpisodeNumbers = [episode],
    };

    private static IEnumerable<ArrRelease> Singles(int count) => Missing.Take(count).Select(e => Single(e));

    [Fact]
    public void ALightPackWins() =>
        Assert.Equal("pack", SeasonPackRule.ChoosePack(Singles(10).Append(Pack(11)), Missing, PerEpisode)?.Guid);

    [Fact]
    public void AHeavyPackLoses() =>
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10).Append(Pack(14)), Missing, PerEpisode));

    [Fact]
    public void AMissingSingleTakesThePack() =>
        Assert.Equal("pack", SeasonPackRule.ChoosePack(Singles(9).Append(Pack(14)), Missing, PerEpisode)?.Guid);

    [Fact]
    public void AnAnimeSingleWithOnlyMappedNumbersCountsAsASingle()
    {
        var anime = Singles(9).Append(new ArrRelease { Guid = "ep10", Size = Gb, CustomFormatScore = 100, MappedEpisodeNumbers = [10] });

        // Con tutti i singoli il pack pesante perde; senza quello dell'episodio 10 vincerebbe.
        Assert.Null(SeasonPackRule.ChoosePack(anime.Append(Pack(14)), Missing, PerEpisode));
    }

    [Fact]
    public void LaterPacksMustBeLightEnoughToo()
    {
        // I singoli pesano 10 GB: un pack si prende fino a 12 GB, anche il secondo o il terzo.
        ArrRelease Other(string guid, double gb) => new() { Guid = guid, Size = (long)(gb * Gb), CustomFormatScore = 100, FullSeason = true };

        var packs = SeasonPackRule.PackCandidates(Singles(10).Append(Pack(11)).Append(Other("heavy", 13)).Append(Other("ok", 11.5)), Missing, PerEpisode);

        Assert.Equal(["pack", "ok"], packs.Select(p => p.Guid));
    }

    [Fact]
    public void WithoutAllSinglesEveryValidPackIsACandidate()
    {
        ArrRelease Other(string guid, double gb) => new() { Guid = guid, Size = (long)(gb * Gb), CustomFormatScore = 100, FullSeason = true };

        Assert.Equal(["pack", "heavy"], SeasonPackRule.PackCandidates(Singles(9).Append(Pack(11)).Append(Other("heavy", 13)), Missing, PerEpisode).Select(p => p.Guid));
    }

    [Fact]
    public void APackIsSizeCheckedOnTheWholeSeason()
    {
        // 2 episodi mancanti su 10 da 24 minuti: il massimo di Sonarr (100 MB/min) si misura su 240 minuti, non su 48.
        var checks = new ChecksContext(
            null, [new ArrQualityDefinition { Quality = new ArrQuality { Id = 3 }, MinSize = 1, MaxSize = 100 }], [], [], new Dictionary<int, int>(), []);
        var input = new RuleInput(24, false, 0, 0, new Dictionary<int, int>(), checks);
        var pack = new ArrRelease
        {
            Guid = "pack", Size = 20 * Gb, FullSeason = true, Source = ReleaseSource.Prowlarr,
            Quality = new ArrQualityModel { Quality = new ArrQuality { Id = 3 } }, EpisodeNumbers = [.. Missing],
        };

        Assert.Equal("pack", SeasonPackRule.Packs([pack], 2, input).Choice?.Guid);
    }

    [Fact]
    public void NothingValidSplits()
    {
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10).Append(Pack(11, "Unknown series")), Missing, PerEpisode));
        Assert.Null(SeasonPackRule.ChoosePack(Singles(10), Missing, PerEpisode));
    }

    private static ArrRelease Pack720(string guid, double gb, int score = 100) => new()
    {
        Guid = guid,
        Size = (long)(gb * Gb),
        CustomFormatScore = score,
        FullSeason = true,
        Quality = new ArrQualityModel { Quality = new ArrQuality { Id = 4, Name = "HDTV-720p", Resolution = 720 } },
        Rejections = ["HDTV-720p is not wanted in profile"],
    };

    private static ArrRelease Single720(int episode) => new()
    {
        Guid = "ep720-" + episode,
        Size = Gb,
        CustomFormatScore = 100,
        EpisodeNumbers = [episode],
        Quality = new ArrQualityModel { Quality = new ArrQuality { Id = 4, Name = "HDTV-720p", Resolution = 720 } },
        Rejections = ["HDTV-720p is not wanted in profile"],
    };

    [Fact]
    public void QualityPackWhenOnly720pPacks()
    {
        var result = SeasonPackRule.QualityPack([Pack720("low", 11, 10), Pack720("best", 11, 90)], Missing, PerEpisode);

        Assert.NotNull(result);
        Assert.Equal("best", DownloadRule.ChooseStopgap(result).Release?.Guid);
    }

    [Fact]
    public void NoQualityPackWithA1080pSingle()
    {
        // Il singolo 1080p è ammesso anche se sotto il punteggio minimo: la stagione si divide.
        var single = Single(1);
        single.CustomFormatScore = 0;

        Assert.Null(SeasonPackRule.QualityPack([Pack720("p", 11), single], Missing, PerEpisode));
    }

    [Fact]
    public void NoQualityPackWithALight1080pPack() =>
        Assert.Null(SeasonPackRule.QualityPack([Pack720("p", 11), Pack(0.5)], Missing, PerEpisode));

    [Fact]
    public void NoQualityPackFrom720pSinglesOnly() =>
        Assert.Null(SeasonPackRule.QualityPack(Missing.Select(Single720), Missing, PerEpisode));

    [Fact]
    public void QualityPackMeasuresTheWholeSeason()
    {
        // 2 GB passano il peso minimo sui soli 2 episodi mancanti (90 min), non su 10 (450 min).
        Assert.NotNull(SeasonPackRule.QualityPack([Pack720("p", 2)], [1, 2], PerEpisode));
        Assert.Null(SeasonPackRule.QualityPack([Pack720("p", 2)], Missing, PerEpisode));
        Assert.Null(SeasonPackRule.QualityPack([Pack720("p", 11)], [], PerEpisode));
    }
}
