using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseQueriesTests
{
    private const string Slime = "That Time I Got Reincarnated as a Slime";

    private static SonarrAlternateTitle Scene(string title, int scene) => new() { Title = title, SceneSeasonNumber = scene };

    private static SonarrAlternateTitle General(string title) => new() { Title = title, SeasonNumber = -1 };

    // I titoli alternativi della serie 265 di Sonarr, come li ha mandati il 2026-11-11.
    private static SonarrSeries SlimeSeries() => new()
    {
        Id = 265,
        Title = Slime,
        SeriesType = "anime",
        AlternateTitles =
        [
            Scene("Tensei Shitara Slime Datta Ken S2", 2),
            Scene("Tensei shitara Slime Datta Ken 2nd Season", 2),
            Scene("Tensei Shitara Slime Datta Ken", -1),
            Scene("That Time I Got Reincarnated as a Slime Season 2", 2),
            Scene("Tensei Shitara Slime Datta Ken S3", 3),
            Scene("Tensei shitara Slime Datta Ken 3rd Season", 3),
            Scene("That Time I Got Reincarnated as a Slime Season 3", 3),
            Scene("Tensei Shitara Slime Datta Ken S4", 4),
            Scene("Tensei shitara Slime Datta Ken 4th Season", 4),
            Scene("That Time I Got Reincarnated as a Slime Season 4", 4),
            General("Tensei Shitara Slime Datta Ken That Time I Got Reincarnated as a Slime"),
            General("Vita da Slime"),
            General("Meine Wiedergeburt als Schleim in einer anderen Welt"),
        ],
    };

    [Fact]
    public void SeasonUsesTitleThenSeasonAltTitlesThenGeneral()
    {
        var queries = ReleaseQueries.ForSeason(SlimeSeries(), 2);

        Assert.Equal(
            [
                ("tvsearch", Slime, (int?)2, (int?)null),
                ("search", "Tensei Shitara Slime Datta Ken S2", null, null),
                ("search", "Tensei shitara Slime Datta Ken 2nd Season", null, null),
                ("search", "That Time I Got Reincarnated as a Slime Season 2", null, null),
                ("search", "Tensei Shitara Slime Datta Ken", null, null),
                ("search", "Tensei Shitara Slime Datta Ken That Time I Got Reincarnated as a Slime", null, null),
                ("search", "Vita da Slime", null, null),
                ("search", "Meine Wiedergeburt als Schleim in einer anderen Welt", null, null),
            ],
            queries);
    }

    [Fact]
    public void AnimeEpisodeAddsAbsoluteNumbers()
    {
        var episode = new SonarrEpisode
        {
            SeasonNumber = 2,
            EpisodeNumber = 1,
            AbsoluteEpisodeNumber = 25,
            SceneAbsoluteEpisodeNumber = 1,
            SceneSeasonNumber = 2,
            SceneEpisodeNumber = 1,
        };

        var queries = ReleaseQueries.ForEpisode(SlimeSeries(), episode);

        Assert.Equal(("tvsearch", Slime, 2, 1), queries[0]);
        Assert.Contains(("search", $"{Slime} 25", (int?)null, (int?)null), queries);
        Assert.Contains(("search", "Tensei Shitara Slime Datta Ken S2 01", (int?)null, (int?)null), queries);
        Assert.Contains(("search", "Tensei shitara Slime Datta Ken 2nd Season 01", (int?)null, (int?)null), queries);
        Assert.DoesNotContain(queries, q => q.Query.Contains("S3", StringComparison.Ordinal));
    }

    [Fact]
    public void StandardEpisodeIsOneTvSearch()
    {
        var series = new SonarrSeries { Title = "Severance", SeriesType = "standard", AlternateTitles = [Scene("Severance Alt", 1)] };
        var episode = new SonarrEpisode { SeasonNumber = 1, EpisodeNumber = 3, AbsoluteEpisodeNumber = 3, SceneSeasonNumber = 1, SceneEpisodeNumber = 3 };

        Assert.Equal([("tvsearch", "Severance", (int?)1, (int?)3)], ReleaseQueries.ForEpisode(series, episode));
    }

    [Fact]
    public void MovieUsesYearOriginalAndItalian()
    {
        var movie = new RadarrMovie
        {
            Title = "Ao Haru Ride",
            Year = 2014,
            OriginalTitle = "Aoharaido",
            AlternateTitles =
            [
                new() { Title = "Blue Spring Ride", Language = new() { Name = "English" } },
                new() { Title = "A un passo da te", Language = new() { Name = "Italian" } },
                new() { Title = "Ao Haru Ride DE", Language = new() { Name = "German" } },
                new() { Title = "Senza lingua" },
            ],
        };

        Assert.Equal(
            [
                ("movie", "Ao Haru Ride 2014", (int?)null, (int?)null),
                ("movie", "Aoharaido", null, null),
                ("movie", "A un passo da te", null, null),
                ("movie", "Blue Spring Ride", null, null),
            ],
            ReleaseQueries.ForMovie(movie));
    }

    [Fact]
    public void DuplicatesAndCapRemoved()
    {
        var alts = new List<SonarrAlternateTitle?> { Scene("show  one", 1), Scene("SHOW ONE", 1), Scene("Show One", 1), null, Scene(" ", 1) };
        for (var i = 0; i < 12; i++)
        {
            alts.Add(Scene($"Alt {i}", 1));
        }

        var queries = ReleaseQueries.ForSeason(new SonarrSeries { Title = "Show One", AlternateTitles = alts }, 1);

        Assert.Equal(ReleaseQueries.MaxQueries, queries.Count);
        Assert.Equal(("tvsearch", "Show One", 1, null), queries[0]);
        Assert.Equal("show one", queries[1].Query);
        Assert.Equal("Alt 0", queries[2].Query);
        Assert.Equal(queries.Count, queries.Select(q => (q.Type, q.Query.ToLowerInvariant())).Distinct().Count());

        var movie = new RadarrMovie { Title = "A  B", Year = 2000, OriginalTitle = "a b 2000" };
        Assert.Single(ReleaseQueries.ForMovie(movie));
    }
}
