using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseFinderTests
{
    private readonly FakeArrClient _arr = new();
    private readonly FakeProwlarrClient _prowlarr = new();
    private readonly FakeArrSettings _settings = new();
    private readonly RecordingLogger<ReleaseFinder> _logger = new();

    private static DownloadKey Season => new(DownloadKinds.Season, 5, 1);

    private ReleaseFinder Finder() => new(_arr, _prowlarr, _settings, _logger);

    private static ArrIndexer Indexer(int id, int? prowlarrId, bool interactive = true, int[]? categories = null, int[]? anime = null)
    {
        var fields = new List<ArrField?> { Field("categories", categories ?? [5000, 5070]) };
        if (prowlarrId is { } p)
        {
            fields.Add(Field("baseUrl", $"http://x/prowlarr/{p}/"));
        }

        if (anime is not null)
        {
            fields.Add(Field("animeCategories", anime));
        }

        return new ArrIndexer { Id = id, EnableInteractiveSearch = interactive, Fields = fields };
    }

    private static ArrField Field(string name, object value) => new() { Name = name, Value = JsonSerializer.SerializeToElement(value) };

    private static ProwlarrRelease Found(int indexerId, string guid, string title = "Show S01") =>
        new() { IndexerId = indexerId, Guid = guid, Title = title, Size = 100, Indexer = "idx" };

    private void SeasonSetup(string seriesType = "standard", params ArrIndexer[] indexers)
    {
        _arr.SeriesById = _ => Task.FromResult(new SonarrSeries { Id = 5, Title = "Show", SeriesType = seriesType });
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>(indexers.Length == 0 ? [Indexer(1, 11)] : indexers);

        // Il parse attribuisce ogni release alla serie 5, stagione 1.
        _arr.Parse = (_, _) => Task.FromResult(new ArrParse
        {
            Series = new SonarrSeries { Id = 5 },
            Episodes = [new SonarrEpisode { Id = 1, SeriesId = 5, SeasonNumber = 1, EpisodeNumber = 1 }],
        });
    }

    [Fact]
    public async Task ArrEngineUsesReleaseEndpoint()
    {
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([new ArrRelease { Guid = "g" }]);

        var result = await Finder().SearchAsync(Season, SearchEngine.Arr, CancellationToken.None, TimeSpan.FromSeconds(7));

        Assert.Equal(SearchEngine.Arr, result.Engine);
        Assert.Single(result.Releases);
        Assert.Equal((ArrKind.Sonarr, "seriesId=5&seasonNumber=1"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.Equal(TimeSpan.FromSeconds(7), _arr.LastReleaseTimeout);
        Assert.Empty(_prowlarr.SearchCalls);
        Assert.Empty(_arr.SeriesByIdCalls);
    }

    [Theory]
    [InlineData(DownloadKinds.Movie, 3, 0, ArrKind.Radarr, "movieId=3")]
    [InlineData(DownloadKinds.Episode, 4, 0, ArrKind.Sonarr, "episodeId=4")]
    public async Task ArrEngineQueryPerKind(string kind, int id, int season, ArrKind service, string query)
    {
        await Finder().SearchAsync(new DownloadKey(kind, id, season), SearchEngine.Arr, CancellationToken.None);

        Assert.Equal((service, query), Assert.Single(_arr.SearchReleaseCalls));
    }

    [Fact]
    public async Task NotConfiguredFallsBackToArr()
    {
        _settings.Prowlarr = ArrEndpoint.None;

        var finder = Finder();
        var result = await finder.SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.False(finder.UsesProwlarr);
        Assert.Equal(SearchEngine.Arr, result.Engine);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Empty(_prowlarr.SearchCalls);
    }

    [Fact]
    public async Task ProwlarrSearchesOnlyInteractiveProwlarrIndexers()
    {
        SeasonSetup("standard", Indexer(1, 11), Indexer(2, 12, interactive: false), Indexer(3, null));
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a"), Found(12, "b")]);

        var finder = Finder();
        var result = await finder.SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.True(finder.UsesProwlarr);
        Assert.Equal(SearchEngine.Prowlarr, result.Engine);
        Assert.All(_prowlarr.SearchCalls, c => Assert.Equal([11], c.IndexerIds));
        Assert.Empty(_arr.SearchReleaseCalls);

        // Il risultato porta l'id del servizio; la release di un indexer fuori mappa è scartata.
        var release = Assert.Single(result.Releases);
        Assert.Equal(1, release!.IndexerId);
        Assert.Equal(ReleaseSource.Prowlarr, release.Source);
        Assert.Equal("Show", _prowlarr.SearchCalls[0].Query);
        Assert.Equal("tvsearch", _prowlarr.SearchCalls[0].Type);
        Assert.Equal(1, _prowlarr.SearchCalls[0].Season);
    }

    [Fact]
    public async Task DeduplicatesByIndexerAndGuid()
    {
        SeasonSetup("standard", Indexer(1, 11), Indexer(2, 12));
        _arr.SeriesById = _ => Task.FromResult(new SonarrSeries
        {
            Id = 5,
            Title = "Show",
            AlternateTitles = [new SonarrAlternateTitle { Title = "Alt", SceneSeasonNumber = -1 }],
        });

        // Due query rispondono con le stesse release; lo stesso guid su un altro indexer resta.
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a"), Found(11, "a"), Found(12, "a")]);

        var result = await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal(2, _prowlarr.SearchCalls.Count);
        Assert.Equal([1, 2], result.Releases.Select(r => r!.IndexerId).Order());
        Assert.Equal(2, _arr.ParseCalls.Count);
    }

    [Fact]
    public async Task WrongTitleSeparated()
    {
        SeasonSetup();
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a", "Show S01"), Found(11, "b", "Other S01")]);
        _arr.Parse = (_, title) => Task.FromResult(new ArrParse
        {
            Series = new SonarrSeries { Id = title == "Show S01" ? 5 : 99 },
            Episodes = [new SonarrEpisode { Id = 1, SeriesId = 5, SeasonNumber = 1, EpisodeNumber = 1 }],
        });

        var result = await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal("Show S01", Assert.Single(result.Releases)!.Title);
        var wrong = Assert.Single(result.WrongTitle);
        Assert.Equal("Other S01", wrong.Title);
        Assert.NotNull(wrong.WrongTitle);
    }

    [Fact]
    public async Task OneFailedQueryIsSkipped()
    {
        SeasonSetup();
        _arr.SeriesById = _ => Task.FromResult(new SonarrSeries
        {
            Id = 5,
            Title = "Show",
            AlternateTitles = [new SonarrAlternateTitle { Title = "Alt", SceneSeasonNumber = -1 }],
        });
        _prowlarr.Search = q => q.Query == "Show"
            ? Task.FromException<IReadOnlyList<ProwlarrRelease>>(new ArrException(ArrError.Unreachable))
            : Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a")]);

        var result = await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Single(result.Releases);
        var warning = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.DoesNotContain("Show", warning.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Alt", warning.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AllQueriesFailedThrows()
    {
        SeasonSetup();
        _prowlarr.Search = _ => Task.FromException<IReadOnlyList<ProwlarrRelease>>(new ArrException(ArrError.Unauthorized));

        var error = await Assert.ThrowsAsync<ArrException>(() => Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None));

        Assert.Equal(ArrError.Unauthorized, error.Error);
    }

    [Fact]
    public async Task OneFailedParseIsSkipped()
    {
        SeasonSetup();
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a", "Show S01"), Found(11, "b", "Broken S01")]);
        _arr.Parse = (_, title) => title == "Broken S01"
            ? Task.FromException<ArrParse>(new ArrException(ArrError.Unreachable) { TimedOut = true })
            : Task.FromResult(new ArrParse
            {
                Series = new SonarrSeries { Id = 5 },
                Episodes = [new SonarrEpisode { Id = 1, SeriesId = 5, SeasonNumber = 1, EpisodeNumber = 1 }],
            });

        var result = await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal("Show S01", Assert.Single(result.Releases)!.Title);
        Assert.Empty(result.WrongTitle);
        var warning = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.DoesNotContain("Broken", warning.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AllParsesFailedThrows()
    {
        SeasonSetup();
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a"), Found(11, "b")]);
        _arr.Parse = (_, _) => Task.FromException<ArrParse>(new ArrException(ArrError.Unauthorized));

        var error = await Assert.ThrowsAsync<ArrException>(() => Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None));

        Assert.Equal(ArrError.Unauthorized, error.Error);
    }

    [Fact]
    public async Task ReadingFailureThrows()
    {
        SeasonSetup();
        _arr.Indexers = _ => Task.FromException<IReadOnlyList<ArrIndexer?>>(new ArrException(ArrError.Unreachable));

        await Assert.ThrowsAsync<ArrException>(() => Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None));

        Assert.Empty(_prowlarr.SearchCalls);
    }

    [Fact]
    public async Task AnimeUsesAnimeCategories()
    {
        SeasonSetup("anime", Indexer(1, 11, categories: [5000, 5070], anime: [5070]), Indexer(2, 12, categories: [5000]), Indexer(3, 13, categories: [5000], anime: [5070]));

        await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        // Gli indexer con le stesse categorie viaggiano insieme: 11 e 13 con 5070, 12 con le sue 5000.
        Assert.Equal(2, _prowlarr.SearchCalls.Count);
        Assert.Contains(_prowlarr.SearchCalls, c => c.IndexerIds.Order().SequenceEqual([11, 13]) && c.Categories.SequenceEqual([5070]));
        Assert.Contains(_prowlarr.SearchCalls, c => c.IndexerIds.SequenceEqual([12]) && c.Categories.SequenceEqual([5000]));
    }

    [Fact]
    public async Task NonAnimeIgnoresAnimeCategories()
    {
        SeasonSetup("standard", Indexer(1, 11, categories: [5000, 5070], anime: [5070]));

        await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal([5000, 5070], Assert.Single(_prowlarr.SearchCalls).Categories);
    }

    [Fact]
    public async Task EpisodeReadsEpisodeThenSeries()
    {
        SeasonSetup();
        _arr.EpisodeById = _ => Task.FromResult(new SonarrEpisode { Id = 4, SeriesId = 5, SeasonNumber = 1, EpisodeNumber = 2 });
        _arr.Parse = (_, _) => Task.FromResult(new ArrParse
        {
            Series = new SonarrSeries { Id = 5 },
            Episodes = [new SonarrEpisode { Id = 4, SeriesId = 5, SeasonNumber = 1, EpisodeNumber = 2 }],
        });
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a")]);

        var result = await Finder().SearchAsync(new DownloadKey(DownloadKinds.Episode, 4, 0), SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal([4], _arr.EpisodeByIdCalls);
        Assert.Equal([5], _arr.SeriesByIdCalls);
        Assert.Equal(2, Assert.Single(_prowlarr.SearchCalls).Episode);
        Assert.Single(result.Releases);
        Assert.Empty(result.WrongTitle);
    }

    [Fact]
    public async Task MovieUsesRadarr()
    {
        _arr.MovieById = _ => Task.FromResult(new RadarrMovie { Id = 3, Title = "Film", Year = 2020, OriginalTitle = "Film" });
        _arr.Indexers = k => Task.FromResult<IReadOnlyList<ArrIndexer?>>(k == ArrKind.Radarr ? [Indexer(1, 11)] : []);
        _arr.Parse = (_, _) => Task.FromResult(new ArrParse { Movie = new RadarrMovie { Id = 3 } });
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>([Found(11, "a", "Film 2020")]);

        var result = await Finder().SearchAsync(new DownloadKey(DownloadKinds.Movie, 3, 0), SearchEngine.Prowlarr, CancellationToken.None);

        Assert.Equal([ArrKind.Radarr], _arr.IndexerCalls);
        Assert.All(_arr.ParseCalls, c => Assert.Equal(ArrKind.Radarr, c.Kind));
        Assert.Equal("movie", _prowlarr.SearchCalls[0].Type);
        Assert.Single(result.Releases);
    }
}
