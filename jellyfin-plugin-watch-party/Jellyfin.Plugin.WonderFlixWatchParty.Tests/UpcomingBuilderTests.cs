using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingBuilderTests
{
    private static readonly DateTimeOffset From = new(2026, 10, 10, 2, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset To = From.AddDays(7);
    private static readonly ArrImage Poster = new() { CoverType = "poster", RemoteUrl = "https://artworks.thetvdb.com/p.jpg" };
    private static readonly ArrImage Fanart = new() { CoverType = "fanart", RemoteUrl = "https://artworks.thetvdb.com/f.jpg" };

    private static SonarrSeries Bear() => new()
    {
        Title = "The Bear", TvdbId = 136311, TmdbId = 136315, ImdbId = "tt14452776", Images = [Poster, Fanart],
    };

    private static SonarrSeries Andor() => new()
    {
        Title = "Andor", TvdbId = 393189, TmdbId = 83867, ImdbId = "tt9253284", Images = [],
    };

    private static SonarrEpisode Episode(
        int seriesId, SonarrSeries? series, int season, int number, DateTimeOffset? at, bool hasFile = false, string? title = null) =>
        new()
        {
            SeriesId = seriesId,
            Series = series,
            SeasonNumber = season,
            EpisodeNumber = number,
            AirDateUtc = at,
            HasFile = hasFile,
            Title = title,
        };

    [Fact]
    public void OnlyEpisodesStillToDownloadInsideTheRangeWithANamedSeries()
    {
        var at = From.AddDays(1);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 1, at, title: " Sistema "),
            Episode(1, Bear(), 1, 3, at.AddHours(1), hasFile: true),
            Episode(1, Bear(), 1, 4, From.AddMinutes(-1)),
            Episode(1, Bear(), 1, 5, To),
            Episode(1, Bear(), 1, 6, null),
            Episode(2, null, 1, 1, at),
            Episode(3, new SonarrSeries { Title = " " }, 1, 1, at),
            null,
        ], From, To);

        var only = Assert.Single(groups);
        Assert.Equal(1, only.SonarrSeriesId);
        Assert.Equal("The Bear", only.SeriesName);
        Assert.Equal(1, only.SeasonNumber);
        Assert.Equal(1, only.EpisodeNumber);
        Assert.Null(only.LastEpisodeNumber);
        Assert.Equal("Sistema", only.EpisodeTitle);
        Assert.Equal(at, only.AirDateUtc);
        Assert.Empty(only.LibrarySeriesIds);
    }

    [Fact]
    public void ConsecutiveEpisodesOutTogetherBecomeOneEntry()
    {
        var first = From.AddDays(1);
        var later = From.AddDays(2);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 9, later),
            Episode(1, Bear(), 1, 6, first, title: "Sei"),
            Episode(2, Andor(), 1, 1, first, title: "Uno"),
            Episode(1, Bear(), 1, 8, first),
            Episode(1, Bear(), 2, 1, first),
            Episode(1, Bear(), 1, 5, first, title: "Cinque"),
        ], From, To);

        // E05 ed E06 escono insieme: una voce, senza titolo. E08 c'è un buco,
        // S02E01 è un'altra stagione, E09 esce un altro giorno: voci a sé.
        Assert.Equal(
            new (string, int, int, int?, string?, DateTimeOffset)[]
            {
                ("Andor", 1, 1, null, "Uno", first),
                ("The Bear", 1, 5, 6, null, first),
                ("The Bear", 1, 8, null, null, first),
                ("The Bear", 2, 1, null, null, first),
                ("The Bear", 1, 9, null, null, later),
            },
            groups.Select(g => (g.SeriesName, g.SeasonNumber, g.EpisodeNumber, g.LastEpisodeNumber, g.EpisodeTitle, g.AirDateUtc)));
    }

    [Fact]
    public void ExternalIdsAndOnlyPublicImageAddresses()
    {
        var shogun = new SonarrSeries
        {
            Title = "Shogun",
            TvdbId = 0,
            TmdbId = 0,
            ImdbId = " ",
            Images =
            [
                null,
                new ArrImage { CoverType = "Poster", RemoteUrl = "/sonarr/MediaCover/7/poster.jpg" },
                new ArrImage { CoverType = "poster", RemoteUrl = " https://image.tmdb.org/t/p/original/p.jpg " },
                new ArrImage { CoverType = "fanart", RemoteUrl = "ftp://example.com/f.jpg" },
                new ArrImage { CoverType = "banner", RemoteUrl = "https://example.com/b.jpg" },
            ],
        };

        var group = Assert.Single(UpcomingBuilder.Episodes([Episode(7, shogun, 1, 1, From.AddDays(1))], From, To));
        Assert.Null(group.TvdbId);
        Assert.Null(group.TmdbId);
        Assert.Null(group.ImdbId);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", group.PosterUrl);
        Assert.Null(group.BackdropUrl);

        var bare = Assert.Single(UpcomingBuilder.Episodes(
            [Episode(8, new SonarrSeries { Title = "X", Images = null }, 1, 1, From.AddDays(1))], From, To));
        Assert.Null(bare.PosterUrl);
        Assert.Null(bare.BackdropUrl);

        var bear = Assert.Single(UpcomingBuilder.Episodes([Episode(1, Bear(), 1, 1, From.AddDays(1))], From, To));
        Assert.Equal(136311, bear.TvdbId);
        Assert.Equal(136315, bear.TmdbId);
        Assert.Equal("tt14452776", bear.ImdbId);
        Assert.Equal("https://artworks.thetvdb.com/p.jpg", bear.PosterUrl);
        Assert.Equal("https://artworks.thetvdb.com/f.jpg", bear.BackdropUrl);
    }

    [Fact]
    public void MoviesWithADigitalReleaseInTheRangeNotYetDownloaded()
    {
        var from = new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero);
        var to = from.AddDays(91);
        RadarrMovie Movie(string title, int tmdb, DateTimeOffset? digital, bool hasFile = false, int year = 2026) => new()
        {
            Title = title,
            TmdbId = tmdb,
            DigitalRelease = digital,
            HasFile = hasFile,
            Year = year,
            Images = [new ArrImage { CoverType = "poster", RemoteUrl = $"https://image.tmdb.org/t/p/original/{tmdb}.jpg" }],
        };

        var movies = UpcomingBuilder.Movies(
        [
            Movie("Odissea", 1368337, from.AddDays(38)),
            Movie("Hope", 1058424, from.AddDays(3), year: 0),
            Movie("Già uscito", 1564614, from.AddDays(-74)),
            Movie("Scaricato", 1, from.AddDays(5), hasFile: true),
            Movie("Solo al cinema", 2, null),
            Movie("Troppo tardi", 3, to),
            Movie("Senza TMDB", 0, from.AddDays(5)),
            Movie(" ", 4, from.AddDays(5)),
            Movie("Oggi", 5, from),
            null,
        ], from, to);

        Assert.Equal(new[] { "Oggi", "Hope", "Odissea" }, movies.Select(m => m.Title));
        var hope = movies[1];
        Assert.Null(hope.Year);
        Assert.Equal(1058424, hope.TmdbId);
        Assert.Equal(from.AddDays(3), hope.DigitalRelease);
        Assert.Equal("https://image.tmdb.org/t/p/original/1058424.jpg", hope.PosterUrl);
        Assert.Null(hope.BackdropUrl);
        Assert.Equal(2026, movies[2].Year);
    }

    [Fact]
    public void SeriesMatchTheLibraryByAnyExternalId()
    {
        var at = From.AddDays(1);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 1, at),
            Episode(2, Andor(), 1, 1, at),
            Episode(3, new SonarrSeries { Title = "Nuova", TvdbId = 999, Images = [] }, 1, 1, at),
        ], From, To);
        var byTvdb = Guid.NewGuid();
        var byTmdb = Guid.NewGuid();
        var byImdb = Guid.NewGuid();

        var matched = UpcomingBuilder.MatchSeries(
            groups,
            [
                new LibrarySeries(byTvdb, "136311", null, null),
                new LibrarySeries(byTmdb, null, "136315", null),
                new LibrarySeries(byImdb, null, null, "TT9253284"),
                new LibrarySeries(Guid.NewGuid(), "1", "2", "tt0"),
            ]);

        // Due serie della libreria per The Bear (es. due librerie): restano tutte e due.
        Assert.Equal(new[] { byTvdb, byTmdb }, matched.Single(g => g.SeriesName == "The Bear").LibrarySeriesIds);
        Assert.Equal(new[] { byImdb }, matched.Single(g => g.SeriesName == "Andor").LibrarySeriesIds);
        Assert.Empty(matched.Single(g => g.SeriesName == "Nuova").LibrarySeriesIds);
    }
}
