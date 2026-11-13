using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ReleaseFinderTests
{
    private readonly FakeArrClient _arr = new();
    private readonly FakeProwlarrClient _prowlarr = new();
    private readonly FakeArrSettings _settings = new();
    private readonly RecordingLogger<ReleaseFinder> _logger = new();

    private static DownloadKey Season => new(DownloadKinds.Season, 5, 1);

    private readonly FakeQbitClient _qbit = new();

    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero));

    // L'attesa fra le letture della cronologia fa solo avanzare l'orologio finto.
    private ReleaseFinder Finder() => new(_arr, _prowlarr, _settings, _logger, _qbit, _time)
    {
        Wait = (delay, _) =>
        {
            _time.Advance(delay);
            return Task.CompletedTask;
        },
    };

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

    // ---- GrabAsync ----

    private const string Magnet = "magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567&dn=Show";

    private static ArrRelease Pushed(string? downloadUrl = null, string? magnet = Magnet) => new()
    {
        Guid = "g",
        IndexerId = 4,
        Title = "Show S01 1080p",
        Size = 123,
        Seeders = 9,
        Source = ReleaseSource.Prowlarr,
        DownloadUrl = downloadUrl,
        MagnetUrl = magnet,
        Protocol = "torrent",
        PublishDate = new DateTimeOffset(2026, 11, 1, 10, 0, 0, TimeSpan.Zero),
    };

    private void Rejects(params string[] reasons) =>
        _arr.Push = (_, _) => Task.FromResult(new ArrPushResult { Rejected = true, Rejections = [.. reasons] });

    [Fact]
    public async Task ArrReleaseIsGrabbedByGuid()
    {
        var result = await Finder().GrabAsync(ArrKind.Sonarr, new ArrRelease { Guid = "g", IndexerId = 3 }, false, CancellationToken.None);

        Assert.Equal(new GrabResult(GrabKind.Grabbed, null, null), result);
        Assert.Equal((ArrKind.Sonarr, "g", 3), Assert.Single(_arr.GrabCalls));
        Assert.Empty(_arr.PushCalls);
    }

    [Fact]
    public async Task PushApprovedIsGrabbed()
    {
        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed("http://prowlarr/dl?apikey=k"), false, CancellationToken.None);

        Assert.Equal(GrabKind.Grabbed, result.Kind);
        Assert.Empty(_arr.GrabCalls);
        var (kind, push) = Assert.Single(_arr.PushCalls);
        Assert.Equal(ArrKind.Sonarr, kind);
        Assert.Equal(
            ("Show S01 1080p", "http://prowlarr/dl?apikey=k", Magnet, "torrent", 123L, 4, 9),
            (push.Title, push.DownloadUrl, push.MagnetUrl, push.Protocol, push.Size, push.IndexerId, push.Seeders));
        Assert.Equal(new DateTimeOffset(2026, 11, 1, 10, 0, 0, TimeSpan.Zero), push.PublishDate);
    }

    [Fact]
    public async Task PushWithoutPublishDateSendsNow()
    {
        var release = Pushed();
        release.PublishDate = null;

        await Finder().GrabAsync(ArrKind.Sonarr, release, false, CancellationToken.None);

        Assert.Equal(_time.GetUtcNow(), Assert.Single(_arr.PushCalls).Release.PublishDate);
    }

    [Fact]
    public async Task PushTemporarilyRejectedIsPending()
    {
        _arr.Push = (_, _) => Task.FromResult(new ArrPushResult { TemporarilyRejected = true, Rejections = ["Waiting for better quality"] });

        Assert.Equal(GrabKind.Pending, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task IntentionalNotUpgradeGoesDirect()
    {
        Rejects("Existing file on disk is of equal or higher preference: Bluray-1080p", "Not an upgrade for existing episode file(s)");
        _qbit.AddedHash = "0123456789abcdef0123456789abcdef01234567";

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None);

        Assert.Equal(new GrabResult(GrabKind.Direct, null, "0123456789abcdef0123456789abcdef01234567"), result);
        Assert.Equal((Magnet, "series"), Assert.Single(_qbit.Added));
    }

    [Fact]
    public async Task DirectWithoutMagnetAddsTheTorrentLinkInRadarrCategory()
    {
        Rejects("movie is not monitored");

        var result = await Finder().GrabAsync(ArrKind.Radarr, Pushed("http://prowlarr/dl", magnet: null), true, CancellationToken.None);

        Assert.Equal(GrabKind.Direct, result.Kind);
        Assert.Equal(("http://prowlarr/dl", "radarr"), Assert.Single(_qbit.Added));
    }

    [Fact]
    public async Task NotIntentionalNotUpgradeIsRuleRefused()
    {
        Rejects("Not an upgrade for existing episode file(s)");

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None);

        Assert.Equal(new GrabResult(GrabKind.RuleRefused, "Not an upgrade for existing episode file(s)", null), result);
        Assert.Empty(_qbit.Added);
    }

    [Fact]
    public async Task AnIntentionalGrabRefusedForQualityGoesDirect()
    {
        // Il tappabuchi 720p: il profilo non lo ammette, ma l'admin lo vuole intanto.
        Rejects("HDTV-720p is not wanted in profile");

        Assert.Equal(GrabKind.Direct, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None)).Kind);
        Assert.Equal(GrabKind.RuleRefused, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None)).Kind);
        Assert.Single(_qbit.Added);
    }

    [Fact]
    public async Task MixedRejectionsAreRuleRefused()
    {
        Rejects("Release in queue already meets cutoff", "Quality not wanted");

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None);

        Assert.Equal(new GrabResult(GrabKind.RuleRefused, "Release in queue already meets cutoff", null), result);
        Assert.Empty(_qbit.Added);
    }

    [Fact]
    public async Task UnableToParseIsRuleRefused()
    {
        _arr.Push = (_, _) => Task.FromException<ArrPushResult>(new ArrException(ArrError.Unreachable, status: 400));

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None);

        Assert.Equal(new GrabResult(GrabKind.RuleRefused, "Unable to parse", null), result);
    }

    [Fact]
    public async Task ServerErrorOnPushPasses()
    {
        _arr.Push = (_, _) => Task.FromException<ArrPushResult>(new ArrException(ArrError.Unreachable, status: 500));

        var error = await Assert.ThrowsAsync<ArrException>(() => Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None));
        Assert.Equal(500, error.Status);
    }

    [Fact]
    public async Task IntentionalUnmonitoredEpisodesGoDirect()
    {
        Rejects("One or more episodes is not monitored");

        Assert.Equal(GrabKind.Direct, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task AnApprovedPushIsConfirmedByTheGuidOfThePush()
    {
        // Sonarr normalizza il titolo nella cronologia ("[CB46E567].mkv" → "[CB46E567] mkv", accenti tolti): conta il guid "PUSH-<link>".
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>(
        [
            new ArrHistoryRecord { SourceTitle = "Other", Data = new() { ["guid"] = "PUSH-http://other" } },
            new ArrHistoryRecord { SourceTitle = "Show S01 1080p mkv", Data = new() { ["guid"] = "PUSH-http://prowlarr/dl?apikey=k" } },
        ]);

        var result = await Finder().GrabAsync(ArrKind.Radarr, Pushed("http://prowlarr/dl?apikey=k"), false, CancellationToken.None);

        Assert.Equal(GrabKind.Grabbed, result.Kind);
        var (kind, since) = Assert.Single(_arr.HistoryCalls);
        Assert.Equal((ArrKind.Radarr, _time.GetUtcNow() - TimeSpan.FromSeconds(10)), (kind, since));
    }

    public static TheoryData<string, string?, ArrHistoryRecord> Matches => new()
    {
        { "guid col magnet", null, new ArrHistoryRecord { Data = new() { ["guid"] = "PUSH-" + Magnet } } },
        { "downloadUrl", "http://prowlarr/dl", new ArrHistoryRecord { Data = new() { ["downloadUrl"] = "http://prowlarr/dl" } } },
        { "downloadId", null, new ArrHistoryRecord { DownloadId = "0123456789ABCDEF0123456789ABCDEF01234567" } },
        { "torrentInfoHash", null, new ArrHistoryRecord { Data = new() { ["torrentInfoHash"] = "0123456789ABCDEF0123456789ABCDEF01234567" } } },
        { "serie", null, new ArrHistoryRecord { SeriesId = 5, Date = new DateTimeOffset(2026, 11, 11, 11, 59, 56, TimeSpan.Zero) } },
        { "episodio", null, new ArrHistoryRecord { EpisodeId = 9, Date = new DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero) } },
    };

    [Theory]
    [MemberData(nameof(Matches))]
    public async Task AGrabRecordOfThePushConfirmsIt(string rule, string? downloadUrl, ArrHistoryRecord record)
    {
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>([record]);
        var release = Pushed(downloadUrl);
        (release.TitleId, release.EpisodeId) = (5, 9);

        Assert.True(GrabKind.Grabbed == (await Finder().GrabAsync(ArrKind.Sonarr, release, false, CancellationToken.None)).Kind, rule);
    }

    // Nyaa: magnetUrl di Prowlarr è un link http. Dalla ricerca al grab deve viaggiare come downloadUrl, mai come magnet.
    private async Task<ArrRelease> FoundWithHttpMagnet()
    {
        const string Link = "http://prowlarr/8/download?file=x";
        SeasonSetup();
        _prowlarr.Search = _ => Task.FromResult<IReadOnlyList<ProwlarrRelease>>(
            [new ProwlarrRelease { IndexerId = 11, Guid = "n", Title = "Show S01", Size = 100, Indexer = "Nyaa.si", MagnetUrl = Link }]);
        var result = await Finder().SearchAsync(Season, SearchEngine.Prowlarr, CancellationToken.None);
        return result.Releases.Single()!;
    }

    [Fact]
    public async Task AnHttpMagnetUrlIsPushedAsDownloadUrlAndConfirmedByIt()
    {
        var release = await FoundWithHttpMagnet();
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>(
            [new ArrHistoryRecord { Data = new() { ["guid"] = "PUSH-http://prowlarr/8/download?file=x" } }]);

        var result = await Finder().GrabAsync(ArrKind.Sonarr, release, false, CancellationToken.None);

        Assert.Equal(GrabKind.Grabbed, result.Kind);
        var push = Assert.Single(_arr.PushCalls).Release;
        Assert.Equal("http://prowlarr/8/download?file=x", push.DownloadUrl);
        Assert.Null(push.MagnetUrl);
    }

    [Fact]
    public async Task AnHttpMagnetUrlGoesToQbittorrentAsALinkToDownload()
    {
        var release = await FoundWithHttpMagnet();
        Rejects("movie is not monitored");

        var result = await Finder().GrabAsync(ArrKind.Sonarr, release, true, CancellationToken.None);

        Assert.Equal(GrabKind.Direct, result.Kind);
        Assert.Equal(("http://prowlarr/8/download?file=x", "series"), Assert.Single(_qbit.Added));
    }

    [Fact]
    public async Task AMovieGrabIsConfirmedByTheMovieId()
    {
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>(
            [new ArrHistoryRecord { MovieId = 12, Date = _time.GetUtcNow() }, new ArrHistoryRecord { SeriesId = 12, Date = _time.GetUtcNow() }]);
        var release = Pushed("http://prowlarr/x");
        release.TitleId = 12;

        Assert.Equal(GrabKind.Grabbed, (await Finder().GrabAsync(ArrKind.Radarr, release, false, CancellationToken.None)).Kind);

        // Per Radarr seriesId non conta.
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>([new ArrHistoryRecord { SeriesId = 12, Date = _time.GetUtcNow() }]);
        Assert.Equal(GrabKind.ClientRefused, (await Finder().GrabAsync(ArrKind.Radarr, release, false, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task AnOlderGrabOfTheSameTitleOrAnEqualTitleDoesNotConfirm()
    {
        // Un grab della stessa serie di prima del push (oltre 5 s), o solo lo stesso titolo: non è il nostro.
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>(
        [
            new ArrHistoryRecord { SeriesId = 5, Date = new DateTimeOffset(2026, 11, 11, 11, 59, 54, TimeSpan.Zero) },
            new ArrHistoryRecord { SourceTitle = "Show S01 1080p" },
        ]);
        var release = Pushed("http://prowlarr/x");
        release.TitleId = 5;

        Assert.Equal(GrabKind.ClientRefused, (await Finder().GrabAsync(ArrKind.Sonarr, release, false, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task TheConfirmWindowStartsWhenThePushAnswers()
    {
        // Un push lento (10 s): si aspetta il grab ancora 15 s dopo la risposta.
        var start = _time.GetUtcNow();
        _arr.Push = (_, _) =>
        {
            _time.Advance(TimeSpan.FromSeconds(10));
            return Task.FromResult(new ArrPushResult { Approved = true });
        };
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>([]);

        Assert.Equal(GrabKind.ClientRefused, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None)).Kind);
        Assert.InRange(_time.GetUtcNow() - start, TimeSpan.FromSeconds(25), TimeSpan.FromSeconds(27));
    }

    [Fact]
    public async Task AGrabThatShowsUpLaterIsGrabbed()
    {
        var calls = 0;
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>(
            ++calls < 3 ? [] : [new ArrHistoryRecord { Data = new() { ["guid"] = "PUSH-" + Magnet } }]);

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None);

        Assert.Equal(GrabKind.Grabbed, result.Kind);
        Assert.Equal(3, _arr.HistoryCalls.Count);
    }

    [Fact]
    public async Task AnApprovedPushWithoutAGrabIsClientRefused()
    {
        // Sonarr dice "approvata" anche quando qBittorrent rifiuta il torrent (per esempio perché c'è già).
        var start = _time.GetUtcNow();
        _arr.History = (_, _) => Task.FromResult<IReadOnlyList<ArrHistoryRecord?>>([new ArrHistoryRecord { SourceTitle = "Other", EventType = "grabbed" }]);

        var result = await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None);

        Assert.Equal(GrabKind.ClientRefused, result.Kind);
        Assert.True(_arr.HistoryCalls.Count > 2);
        Assert.InRange(_time.GetUtcNow() - start, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(17));
    }

    [Fact]
    public async Task AHistoryThatDoesNotAnswerKeepsTheGrab()
    {
        _arr.History = (_, _) => Task.FromException<IReadOnlyList<ArrHistoryRecord?>>(new ArrException(ArrError.Unreachable, status: 500));

        Assert.Equal(GrabKind.Grabbed, (await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task APendingPushIsNotConfirmed()
    {
        _arr.Push = (_, _) => Task.FromResult(new ArrPushResult { TemporarilyRejected = true });

        await Finder().GrabAsync(ArrKind.Sonarr, Pushed(), false, CancellationToken.None);

        Assert.Empty(_arr.HistoryCalls);
    }

    [Fact]
    public async Task APush400IsLoggedWithItsStatus()
    {
        _arr.Push = (_, _) => Task.FromException<ArrPushResult>(new ArrException(ArrError.Unreachable, status: 400));

        await Finder().GrabAsync(ArrKind.Sonarr, Pushed("http://prowlarr/dl?apikey=secret"), true, CancellationToken.None);

        var entry = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Contains("400", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Show", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("secret", entry.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task DirectWithoutQbitCategoryFails()
    {
        Rejects("Not an upgrade for existing episode file(s)");
        _arr.DownloadClients = _ => Task.FromResult<IReadOnlyList<ArrDownloadClient?>>([new ArrDownloadClient { Enable = true, Implementation = "Transmission" }]);

        await Assert.ThrowsAsync<Space.QbitException>(() => Finder().GrabAsync(ArrKind.Sonarr, Pushed(), true, CancellationToken.None));
        Assert.Empty(_qbit.Added);
    }
}
