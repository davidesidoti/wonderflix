using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ParsedReleaseTests
{
    private static readonly DownloadKey Season2 = new(DownloadKinds.Season, 265, 2);

    private static ProwlarrRelease Found(string guid = "g1") => new()
    {
        Guid = guid,
        IndexerId = 9,
        Indexer = "Knaben",
        Title = "Show S02 1080p WEB-DL",
        Size = 5_000,
        Seeders = 12,
        DownloadUrl = "http://p/dl",
        MagnetUrl = "magnet:?xt=1",
        Protocol = "torrent",
        PublishDate = new DateTimeOffset(2026, 11, 1, 0, 0, 0, TimeSpan.Zero),
    };

    private static SonarrEpisode Ep(int id, int season, int number, int seriesId = 265) =>
        new() { Id = id, SeriesId = seriesId, SeasonNumber = season, EpisodeNumber = number };

    private static ArrParse SeasonParse(int seriesId, int season, params int[] numbers) => new()
    {
        ParsedEpisodeInfo = new ArrParsedInfo
        {
            FullSeason = numbers.Length > 1,
            SeasonNumber = season,
            Quality = new ArrQualityModel { Quality = new ArrQuality { Id = 3, Name = "WEBDL-1080p" } },
        },
        Series = new SonarrSeries { Id = seriesId },
        Episodes = numbers.Select(n => (SonarrEpisode?)Ep(1000 + n, season, n, seriesId)).ToList(),
        CustomFormatScore = 40,
    };

    [Fact]
    public void MapsQualityScoreAndSeasonEpisodes()
    {
        var release = ParsedRelease.From(Found(), SeasonParse(265, 2, 1, 2, 3), 77, Season2);

        Assert.Null(release.WrongTitle);
        Assert.Equal("g1", release.Guid);
        Assert.Equal(77, release.IndexerId);
        Assert.Equal("Knaben", release.Indexer);
        Assert.Equal("Show S02 1080p WEB-DL", release.Title);
        Assert.Equal(5_000, release.Size);
        Assert.Equal(12, release.Seeders);
        Assert.Equal(3, release.Quality!.Quality!.Id);
        Assert.Equal(40, release.CustomFormatScore);
        Assert.True(release.FullSeason);
        Assert.Equal(2, release.SeasonNumber);
        Assert.Equal(new[] { 1, 2, 3 }, release.EpisodeNumbers);
        Assert.Equal(new[] { 1, 2, 3 }, release.MappedEpisodeNumbers);
        Assert.Equal((265, (int?)null), (release.TitleId, release.EpisodeId));
        Assert.False(release.Rejected);
        Assert.Empty(release.Rejections!);
        Assert.Equal(ReleaseSource.Prowlarr, release.Source);
        Assert.Equal("torrent", release.Protocol);
        Assert.Equal("http://p/dl", release.DownloadUrl);
        Assert.Equal(Found().PublishDate, release.PublishDate);
    }

    [Fact]
    public void MagnetOnlyKeepsMagnet()
    {
        var found = Found();
        found.DownloadUrl = null;

        var release = ParsedRelease.From(found, SeasonParse(265, 2, 1), 77, Season2);

        Assert.Null(release.DownloadUrl);
        Assert.Equal("magnet:?xt=1", release.MagnetUrl);
    }

    [Fact]
    public void AnHttpMagnetUrlIsTheDownloadLink()
    {
        // Nyaa: Prowlarr dà in magnetUrl il suo link http (che rimanda a un magnet) e nessun downloadUrl.
        var found = Found();
        (found.DownloadUrl, found.MagnetUrl) = (null, "http://p/8/download?file=x");

        var release = ParsedRelease.From(found, SeasonParse(265, 2, 1), 77, Season2);

        Assert.Equal("http://p/8/download?file=x", release.DownloadUrl);
        Assert.Null(release.MagnetUrl);
    }

    [Fact]
    public void AnHttpMagnetUrlNeverReplacesTheDownloadUrl()
    {
        var found = Found();
        found.MagnetUrl = "HTTP://p/8/download";

        var release = ParsedRelease.From(found, SeasonParse(265, 2, 1), 77, Season2);

        Assert.Equal("http://p/dl", release.DownloadUrl);
        Assert.Null(release.MagnetUrl);
    }

    [Fact]
    public void ARealMagnetIsKeptWhateverItsCase()
    {
        var found = Found();
        found.MagnetUrl = "MAGNET:?xt=1";

        Assert.Equal("MAGNET:?xt=1", ParsedRelease.From(found, SeasonParse(265, 2, 1), 77, Season2).MagnetUrl);
    }

    [Fact]
    public void UsesServiceIndexerId() =>
        Assert.Equal(5, ParsedRelease.From(Found(), SeasonParse(265, 2, 1), 5, Season2).IndexerId);

    [Fact]
    public void OtherSeriesIsWrongTitle() =>
        Assert.NotNull(ParsedRelease.From(Found(), SeasonParse(999, 2, 1), 77, Season2).WrongTitle);

    [Fact]
    public void NoSeriesIsWrongTitle()
    {
        var parse = SeasonParse(265, 2, 1);
        parse.Series = null;

        Assert.NotNull(ParsedRelease.From(Found(), parse, 77, Season2).WrongTitle);
    }

    [Fact]
    public void OtherSeasonIsWrongTitle() =>
        Assert.NotNull(ParsedRelease.From(Found(), SeasonParse(265, 3, 1, 2), 77, Season2).WrongTitle);

    [Fact]
    public void EpisodeCoveredIsMapped()
    {
        var release = ParsedRelease.From(Found(), SeasonParse(265, 2, 4, 5), 77, new DownloadKey(DownloadKinds.Episode, 1005, 0));

        Assert.Null(release.WrongTitle);
        Assert.Equal(2, release.SeasonNumber);
        Assert.Equal(new[] { 4, 5 }, release.EpisodeNumbers);
        Assert.Equal((265, (int?)1005), (release.TitleId, release.EpisodeId));
    }

    [Fact]
    public void EpisodeNotCoveredIsWrongTitle() =>
        Assert.NotNull(ParsedRelease.From(Found(), SeasonParse(265, 2, 4, 5), 77, new DownloadKey(DownloadKinds.Episode, 1006, 0)).WrongTitle);

    [Fact]
    public void MovieMapsQualityAndChecksId()
    {
        var parse = new ArrParse
        {
            ParsedMovieInfo = new ArrParsedInfo { Quality = new ArrQualityModel { Quality = new ArrQuality { Id = 7 } } },
            Movie = new RadarrMovie { Id = 12 },
            CustomFormatScore = 5,
        };

        var ok = ParsedRelease.From(Found(), parse, 77, new DownloadKey(DownloadKinds.Movie, 12, 0));
        Assert.Null(ok.WrongTitle);
        Assert.Equal(7, ok.Quality!.Quality!.Id);
        Assert.Null(ok.EpisodeNumbers);
        Assert.False(ok.FullSeason);
        Assert.Equal((12, (int?)null), (ok.TitleId, ok.EpisodeId));

        Assert.NotNull(ParsedRelease.From(Found(), parse, 77, new DownloadKey(DownloadKinds.Movie, 13, 0)).WrongTitle);
    }
}
