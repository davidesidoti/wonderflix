using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceScanTests : IDisposable
{
    private const string MovieFolder = "/srv/media/movies/Coco (2017)";
    private const string MoviePath = MovieFolder + "/Coco.mkv";
    private const string SeriesFolder = "/srv/media/tv/Serie";
    private const long Gb = 1_000_000_000;

    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeArrClient _arr = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeQbitClient _qbit = new();
    private readonly FakeFileProbe _probe = new();
    private readonly FakeSpaceSettings _settings = new() { QbitUrl = "http://127.0.0.1:17541" };
    private readonly FakeViewingFacts _viewing = new();
    private readonly FakeSeriesIndex _index = new();
    private readonly FakeServer _server = new();
    private readonly RatingService _ratings;
    private readonly UserRef _admin;
    private readonly UserRef _anna;
    private readonly UserRef _luca;
    private readonly List<RadarrMovie> _movies = [];
    private readonly SpaceService _service;

    public SpaceScanTests()
    {
        _admin = _server.AddUser("Admin", isAdmin: true);
        _anna = _server.AddUser("Anna");
        _luca = _server.AddUser("Luca");
        _ratings = TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([.. _movies]);
        _service = new SpaceService(
            _arr,
            _seerr,
            new FakeSeerrSettings(),
            _qbit,
            _probe,
            new FakeLibraryRefresh(),
            _settings,
            new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance),
            _viewing,
            _index,
            _ratings,
            _server,
            _time,
            NullLogger<SpaceService>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private DateTimeOffset Now => _time.GetUtcNow();

    /// <summary>Un film in Radarr con il suo file su disco, collegato a Jellyfin; restituisce l'id Jellyfin.</summary>
    private Guid AddMovie(int id, long size, DateTimeOffset? lastPlayed, int links = 1, string? title = null)
    {
        var folder = id == 12 ? MovieFolder : $"/srv/media/movies/Film {id}";
        var path = id == 12 ? MoviePath : folder + "/film.mkv";
        _movies.Add(new RadarrMovie
        {
            Id = id, TmdbId = 1000 + id, Title = title ?? "Coco", Year = 2017, HasFile = true, Runtime = 105, Status = "released",
            SizeOnDisk = size, Path = folder, Added = Now.AddYears(-2),
            MovieFile = new ArrFileRef { Id = id, Path = path, Size = size },
        });
        _probe.Files[path] = new FileStamp(new FileId(1, id), links, size);
        var itemId = Guid.NewGuid();
        _index.Movies.Add(new LibraryMovie(itemId, (1000 + id).ToString(System.Globalization.CultureInfo.InvariantCulture)));
        IReadOnlyList<UserUsage> usage = lastPlayed is { } at ? [new UserUsage(_anna.Id, "Anna", true, true, at)] : [];
        _viewing.Movies[itemId] = new ItemViewing(itemId, Now.AddYears(-2), usage, ["Animazione"]);
        return itemId;
    }

    /// <summary>La serie 5 con le stagioni 1–3 da 2 episodi, tutte viste da Anna un anno fa.</summary>
    private void AddSeries(string status)
    {
        var seriesId = Guid.NewGuid();
        var seen = new[] { new UserUsage(_anna.Id, "Anna", true, true, Now.AddYears(-1)) };
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
        [
            new SonarrSeries
            {
                Id = 5, TvdbId = 81189, Title = "Serie", Status = status, Path = SeriesFolder, Runtime = 45, Added = Now.AddYears(-3),
                Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 6, SizeOnDisk = 6 * Gb },
                Seasons = [.. Enumerable.Range(1, 3).Select(n => new SonarrSeason
                {
                    SeasonNumber = n, Statistics = new SonarrSeasonStatistics { EpisodeFileCount = 2, SizeOnDisk = 2 * Gb },
                })],
            },
        ]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
            [.. Enumerable.Range(1, 3).SelectMany(n => Enumerable.Range(1, 2).Select(e => new ArrFile
            {
                Id = (n * 10) + e, SeasonNumber = n, Size = Gb, Path = $"{SeriesFolder}/S0{n}E0{e}.mkv",
            }))]);
        for (var n = 1; n <= 3; n++)
        {
            for (var e = 1; e <= 2; e++)
            {
                _probe.Files[$"{SeriesFolder}/S0{n}E0{e}.mkv"] = new FileStamp(new FileId(2, (n * 10) + e), 1, Gb);
            }
        }

        _index.Series.Add(new LibrarySeries(seriesId, "81189", null, null));
        _viewing.SeriesById[seriesId] = new ItemViewing(seriesId, Now.AddYears(-3), seen, ["Dramma"]);
        _viewing.SeasonsBySeries[seriesId] = Enumerable.Range(1, 3)
            .ToDictionary(n => n, n => new ItemViewing(Guid.NewGuid(), Now.AddYears(-3), seen, []));
    }

    private async Task<SpaceOverviewDto> ScanAsync(Guid? caller = null)
    {
        await _service.ScanAsync(CancellationToken.None);
        return _service.Overview(caller ?? _admin.Id);
    }

    [Fact]
    public async Task AStaleMovieIsADeleteCandidate()
    {
        var itemId = AddMovie(12, 6 * Gb, Now.AddMonths(-8));

        var overview = await ScanAsync();

        var row = Assert.Single(overview.Delete);
        Assert.Equal(("movie:12", SpaceKinds.Movie, "Coco", 2017), (row.Key, row.Kind, row.Title, row.Year));
        Assert.Equal([SpaceSignalCodes.NobodyWatching], row.Via);
        Assert.Equal("Anna", Assert.Single(row.Viewers).Name);
        Assert.Equal(6 * Gb, row.FreeNowBytes);
        Assert.Equal(itemId.ToString("N"), row.ItemId);
        Assert.Equal(Now, overview.ScannedAt);
        Assert.False(overview.Scanning);
        Assert.Equal(6 * Gb, overview.Breakdown.MoviesBytes);
    }

    [Fact]
    public async Task AKeptOrFavoriteTitleIsHidden()
    {
        var itemId = AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        await _service.ScanAsync(CancellationToken.None);

        _service.Keep("movie:12", "Coco");
        Assert.Empty(_service.Overview(_admin.Id).Delete);
        Assert.Equal("movie:12", Assert.Single(_service.Overview(_admin.Id).Kept).Key);

        _service.Unkeep("movie:12");
        _viewing.Favorites.Add((_admin.Id, itemId));
        Assert.Empty(_service.Overview(_admin.Id).Delete);
        Assert.Single(_service.Overview(_luca.Id).Delete);
    }

    [Fact]
    public async Task AContinuingSeriesOffersOldSeasonsOnly()
    {
        AddSeries("continuing");

        var overview = await ScanAsync();

        Assert.Equal(["season:5:1", "season:5:2"], overview.Delete.Select(r => r.Key).Order());
        Assert.All(overview.Delete, r => Assert.Equal(("series:5", SpaceKinds.Season), (r.SeriesKey, r.Kind)));
        Assert.Equal(2 * Gb, overview.Delete[0].FreeNowBytes);
    }

    [Fact]
    public async Task AnEndedSeriesIsWhole()
    {
        AddSeries("ended");

        var overview = await ScanAsync();

        var row = Assert.Single(overview.Delete);
        Assert.Equal(("series:5", SpaceKinds.Series, (string?)null), (row.Key, row.Kind, row.SeriesKey));
        Assert.Equal(6 * Gb, row.FreeNowBytes);
        Assert.Equal(6 * Gb, overview.Breakdown.SeriesBytes);
    }

    [Fact]
    public async Task SequelComingFromTheRadarrCollection()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        _movies[0].Collection = new ArrCollection { TmdbId = 10 };
        _movies.Add(new RadarrMovie { Id = 13, TmdbId = 1013, Title = "Coco 2", HasFile = false, Status = "announced", Collection = new ArrCollection { TmdbId = 10 } });

        var overview = await ScanAsync();

        Assert.Contains(SpaceSignalCodes.SequelComing, Assert.Single(overview.Delete).Keep);
    }

    [Fact]
    public async Task AHeavyMovieIsInLighten()
    {
        AddMovie(12, 12 * Gb, lastPlayed: null);
        _movies[0].Runtime = 120;
        _movies[0].Added = Now.AddDays(-10);
        _viewing.Movies[_index.Movies[0].Id] = _viewing.Movies[_index.Movies[0].Id] with { Added = Now.AddDays(-10) };

        var overview = await ScanAsync();

        Assert.Empty(overview.Delete);
        var row = Assert.Single(overview.Lighten);
        Assert.Equal(("movie:12", SpaceKinds.Movie, 6.00, 4_000_000_000L), (row.Key, row.Kind, row.GbPerHour, row.ExcessBytes));
    }

    [Fact]
    public async Task TorrentOnlyAndOrphansAreInCleanup()
    {
        _qbit.Torrents.Add(new QbitTorrent { Hash = "t1", Name = "Old", Size = 3 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/srv/seedings" });
        _qbit.Files["t1"] = [new QbitFile { Name = "Old.mkv", Size = 3 * Gb }];
        _probe.Files["/srv/seedings/Old.mkv"] = new FileStamp(new FileId(3, 1), 1, 3 * Gb);
        _probe.Files["/srv/downloads/Lost.mkv"] = new FileStamp(new FileId(3, 2), 1, 2 * Gb);
        _probe.Files["/srv/downloads/Linked.mkv"] = new FileStamp(new FileId(3, 3), 2, 2 * Gb);

        var overview = await ScanAsync();

        var torrent = Assert.Single(overview.Cleanup.Torrents);
        Assert.Equal(("torrent:t1", "tracker.example", true), (torrent.Key, torrent.Tracker, torrent.CanRemoveNow));
        var orphan = Assert.Single(overview.Cleanup.Orphans);
        Assert.Equal(("/srv/downloads/Lost.mkv", 2 * Gb, false), (orphan.Path, orphan.SizeBytes, orphan.Linked));
        Assert.Matches("^file:[0-9a-f]{16}$", orphan.Key);
        Assert.Equal(SpaceKinds.Orphan, _service.LastScan!.Files[orphan.Key].Kind);
        Assert.Equal(3 * Gb, overview.Breakdown.TorrentOnlyBytes);
    }

    [Fact]
    public async Task QbitDownMeansNoOrphans()
    {
        _qbit.Fail = QbitError.Unreachable;
        _probe.Files["/srv/downloads/Lost.mkv"] = new FileStamp(new FileId(3, 2), 1, 2 * Gb);

        var overview = await ScanAsync();

        Assert.Empty(overview.Cleanup.Orphans);
        Assert.Equal("Unreachable", overview.Errors.Qbit);
    }

    [Fact]
    public async Task ADuplicateInAMovieFolder()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        _probe.Files[MovieFolder + "/Coco.old.mkv"] = new FileStamp(new FileId(1, 99), 2, 5 * Gb);

        var overview = await ScanAsync();

        var duplicate = Assert.Single(overview.Cleanup.Duplicates);
        Assert.Equal((MovieFolder + "/Coco.old.mkv", true), (duplicate.Path, duplicate.Linked));
        Assert.Equal("movie:12", _service.LastScan!.Files[duplicate.Key].OwnerKey);
    }

    [Fact]
    public async Task TheScanLinksTitlesToTheirTorrents()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8), links: 2);
        _qbit.Torrents.Add(new QbitTorrent { Hash = "h1", Name = "Coco", Size = 6 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/srv/downloads" });
        _qbit.Files["h1"] = [new QbitFile { Name = "Coco.mkv", Size = 6 * Gb }];
        _probe.Files["/srv/downloads/Coco.mkv"] = new FileStamp(new FileId(1, 12), 2, 6 * Gb);

        var overview = await ScanAsync();

        var title = _service.LastScan!.Titles["movie:12"];
        Assert.Equal(["h1"], title.Hashes);
        Assert.Equal(MoviePath, Assert.Single(title.Files).Path);
        Assert.Equal(6 * Gb, Assert.Single(overview.Delete).FreeNowBytes);
        Assert.Empty(overview.Cleanup.Torrents);
        Assert.Empty(overview.Cleanup.Orphans);
    }

    [Fact]
    public async Task SonarrDownKeepsRadarr()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        _arr.Series = () => throw new ArrException(ArrError.Unreachable);

        var overview = await ScanAsync();

        Assert.Equal("movie:12", Assert.Single(overview.Delete).Key);
        Assert.Equal(("Unreachable", (string?)null), (overview.Errors.Sonarr, overview.Errors.Radarr));
        Assert.Equal("NotConfigured", overview.Errors.Quota);
    }

    [Fact]
    public async Task TheListsAreOrdered()
    {
        AddMovie(12, 3 * Gb, Now.AddMonths(-8));
        AddMovie(13, 5 * Gb, Now.AddMonths(-8));
        var liked = AddMovie(14, 9 * Gb, Now.AddMonths(-8));
        _ratings.Save(_anna.Id, liked, 10, null);
        _ratings.Save(_luca.Id, liked, 10, null);

        var overview = await ScanAsync();

        Assert.Equal(["movie:13", "movie:12", "movie:14"], overview.Delete.Select(r => r.Key));
        Assert.Equal([SpaceSignalCodes.HighRating], overview.Delete[2].Keep);
        Assert.Equal((5.0, 2), (overview.Delete[2].RatingAvg, overview.Delete[2].RatingCount));
    }

    [Fact]
    public async Task AStatTimeoutKeepsThePreviousScan()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        await _service.ScanAsync(CancellationToken.None);
        var first = _service.LastScan;

        _probe.StatFails = new TimeoutException();
        _time.Advance(TimeSpan.FromDays(1));
        await _service.ScanAsync(CancellationToken.None);

        Assert.Same(first, _service.LastScan);
        Assert.False(_service.Scanning);
    }

    [Fact]
    public async Task OneScanAtATime()
    {
        Assert.True(_service.Scanning);
        Task? second = null;
        _qbit.OnGetTorrents = () => second ??= _service.ScanAsync(CancellationToken.None);

        await _service.ScanAsync(CancellationToken.None);

        Assert.True(second!.IsCompleted);
        Assert.Single(_seerr.Listed);
        Assert.False(_service.Scanning);
    }
}
