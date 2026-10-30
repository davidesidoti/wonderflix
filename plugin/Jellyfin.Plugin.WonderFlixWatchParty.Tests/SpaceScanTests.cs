using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
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
            TestDownloads.Create(_arr, _time, _folder.DownloadsFile),
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
        return await _service.OverviewAsync(caller ?? _admin.Id, CancellationToken.None);
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
        Assert.Empty((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Delete);
        Assert.Equal("movie:12", Assert.Single((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Kept).Key);

        _service.Unkeep("movie:12");
        _viewing.Favorites.Add((_admin.Id, itemId));
        Assert.Empty((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Delete);
        Assert.Single((await _service.OverviewAsync(_luca.Id, CancellationToken.None)).Delete);
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
        Assert.Equal((10.0, 2), (overview.Delete[2].RatingAvg, overview.Delete[2].RatingCount));
    }

    [Fact]
    public async Task AFailedFirstScanLeavesNoResult()
    {
        _probe.StatFails = new TimeoutException();

        var overview = await ScanAsync();

        Assert.Null(overview.ScannedAt);
        Assert.False(overview.Scanning);
        Assert.Null(_service.LastScan);
    }

    [Fact]
    public async Task OnlyDeleteRowsCanStart()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        AddMovie(13, 5 * Gb, Now.AddDays(-1));
        await _service.ScanAsync(CancellationToken.None);

        Assert.Equal(SpaceService.StartOutcome.Unknown, _service.Start(SpaceKinds.Movie, "movie:13").Outcome);
        _service.Keep("movie:12", "Coco");
        Assert.Equal(SpaceService.StartOutcome.Unknown, _service.Start(SpaceKinds.Movie, "movie:12").Outcome);
        _service.Unkeep("movie:12");
        Assert.Equal(SpaceService.StartOutcome.Started, _service.Start(SpaceKinds.Movie, "movie:12").Outcome);
    }

    [Fact]
    public async Task AKeptSeriesHidesItsSeasons()
    {
        AddSeries("continuing");
        await _service.ScanAsync(CancellationToken.None);

        _service.Keep("series:5", "Serie");

        Assert.Empty((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Delete);
        Assert.Equal(SpaceService.StartOutcome.Unknown, _service.Start(SpaceKinds.Season, "season:5:1").Outcome);
    }

    [Fact]
    public async Task ASeasonHoldsOnlyItsFilesAndTorrents()
    {
        AddSeries("continuing");
        for (var n = 1; n <= 2; n++)
        {
            var hash = $"s{n}";
            _qbit.Torrents.Add(new QbitTorrent { Hash = hash, Name = hash, Size = 2 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/srv/seedings" });
            _qbit.Files[hash] = [.. Enumerable.Range(1, 2).Select(e => new QbitFile { Name = $"S0{n}/S0{n}E0{e}.mkv", Size = Gb })];
            for (var e = 1; e <= 2; e++)
            {
                var id = new FileId(2, (n * 10) + e);
                _probe.Files[$"{SeriesFolder}/S0{n}E0{e}.mkv"] = new FileStamp(id, 2, Gb);
                _probe.Files[$"/srv/seedings/S0{n}/S0{n}E0{e}.mkv"] = new FileStamp(id, 2, Gb);
            }
        }

        await _service.ScanAsync(CancellationToken.None);

        var season = _service.LastScan!.Titles["season:5:1"];
        Assert.Equal([$"{SeriesFolder}/S01E01.mkv", $"{SeriesFolder}/S01E02.mkv"], season.Files.Select(f => f.Path).Order());
        Assert.Equal(["s1"], season.Hashes);
    }

    [Fact]
    public async Task ARequestWithoutSeasonsCountsForEverySeason()
    {
        AddSeries("continuing");
        _seerr.Requests.Add(new SeerrRequest
        {
            CreatedAt = Now.AddDays(-5),
            Seasons = null!,
            RequestedBy = new SeerrRequestUser { JellyfinUserId = _luca.Id.ToString("N") },
            Media = new SeerrRequestMedia { MediaType = "tv", TvdbId = 81189 },
        });

        var overview = await ScanAsync();

        Assert.All(overview.Delete, r => Assert.Equal("Luca", Assert.Single(r.Requests).Name));
        Assert.All(overview.Delete, r => Assert.Contains(SpaceSignalCodes.RecentRequest, r.Keep));
    }

    // Un orfano vero accanto a quello che la guardia deve scartare.
    private async Task AssertOnlyLostIsOrphanAsync()
    {
        _probe.Files["/srv/downloads/Lost.mkv"] = new FileStamp(new FileId(3, 2), 1, 2 * Gb);
        var overview = await ScanAsync();
        Assert.Equal("/srv/downloads/Lost.mkv", Assert.Single(overview.Cleanup.Orphans).Path);
    }

    [Fact]
    public async Task ALibraryFileIsNeverAnOrphan()
    {
        _movies.Add(new RadarrMovie
        {
            Id = 20, TmdbId = 1020, Title = "Qui", HasFile = true, Path = "/srv/downloads/Qui",
            MovieFile = new ArrFileRef { Id = 20, Path = "/srv/downloads/Qui/qui.mkv", Size = 3 * Gb },
        });
        _probe.Files["/srv/downloads/Qui/qui.mkv"] = new FileStamp(new FileId(4, 1), 1, 3 * Gb);

        await AssertOnlyLostIsOrphanAsync();
    }

    [Fact]
    public async Task AnAliasOfALibraryFileIsNeverAnOrphan()
    {
        AddMovie(12, 6 * Gb, lastPlayed: null);
        _probe.Files["/srv/downloads/Alias.mkv"] = new FileStamp(new FileId(1, 12), 1, 6 * Gb);

        await AssertOnlyLostIsOrphanAsync();
    }

    [Fact]
    public async Task AnAliasOfATorrentFileIsNeverAnOrphan()
    {
        _qbit.Torrents.Add(new QbitTorrent { Hash = "t1", Name = "Old", Size = 3 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/srv/seedings" });
        _qbit.Files["t1"] = [new QbitFile { Name = "Old.mkv", Size = 3 * Gb }];
        _probe.Files["/srv/seedings/Old.mkv"] = new FileStamp(new FileId(3, 1), 1, 3 * Gb);
        _probe.Files["/srv/downloads/Old.mkv"] = new FileStamp(new FileId(3, 1), 1, 3 * Gb);

        await AssertOnlyLostIsOrphanAsync();
    }

    [Fact]
    public async Task AnIncompleteDownloadIsNeverAnOrphan()
    {
        _qbit.Torrents.Add(new QbitTorrent
        {
            Hash = "t2", Name = "Film", Size = 3 * Gb, Progress = 0.5, SavePath = "/srv/seedings", ContentPath = "/srv/downloads/incomplete/Film",
        });
        _qbit.Files["t2"] = [new QbitFile { Name = "Film/film.mkv", Size = 3 * Gb }];
        _probe.Files["/srv/downloads/incomplete/Film/film.mkv"] = new FileStamp(new FileId(5, 1), 1, 3 * Gb);

        await AssertOnlyLostIsOrphanAsync();
    }

    [Fact]
    public async Task AFileOfAnotherTitleIsNeverADuplicate()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        AddMovie(13, 5 * Gb, Now.AddMonths(-8));
        _movies[1].MovieFile!.Path = MovieFolder + "/Other.mkv";
        _probe.Files.Remove("/srv/media/movies/Film 13/film.mkv");
        _probe.Files[MovieFolder + "/Other.mkv"] = new FileStamp(new FileId(1, 13), 1, 5 * Gb);

        var overview = await ScanAsync();

        Assert.Empty(overview.Cleanup.Duplicates);
    }

    [Fact]
    public async Task AHardlinkOfALibraryFileIsNeverADuplicate()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8), links: 2);
        _probe.Files[MovieFolder + "/Coco.copy.mkv"] = new FileStamp(new FileId(1, 12), 2, 6 * Gb);

        var overview = await ScanAsync();

        Assert.Empty(overview.Cleanup.Duplicates);
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
        // Prima del primo calcolo risulta in corso (spec U §7.3).
        Assert.True(_service.Scanning);
        Task? second = null;
        var scanning = false;
        _qbit.OnGetTorrents = () =>
        {
            scanning = _service.Scanning;
            second ??= _service.ScanAsync(CancellationToken.None);
        };

        await _service.ScanAsync(CancellationToken.None);

        Assert.True(scanning);
        Assert.True(second!.IsCompleted);
        Assert.Single(_seerr.Listed);
        Assert.False(_service.Scanning);
    }

    [Fact]
    public async Task AKeptSeasonHidesItsWholeSeries()
    {
        AddSeries("ended");
        await _service.ScanAsync(CancellationToken.None);
        Assert.Equal(["series:5", "season:5:1", "season:5:2", "season:5:3"], _service.LastScan!.Delete.Single().Keys);

        _service.Keep("season:5:2", "Serie - Stagione 2");

        Assert.Empty((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Delete);
        Assert.Equal(SpaceService.StartOutcome.Unknown, _service.Start(SpaceKinds.Series, "series:5").Outcome);
        _service.Unkeep("season:5:2");
        Assert.Equal(SpaceService.StartOutcome.Started, _service.Start(SpaceKinds.Series, "series:5").Outcome);
    }

    private void AddCleanupTorrent(string hash, long inode)
    {
        _qbit.Torrents.Add(new QbitTorrent { Hash = hash, Name = "Old", Size = 3 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/srv/seedings" });
        _qbit.Files[hash] = [new QbitFile { Name = hash + ".mkv", Size = 3 * Gb }];
        _probe.Files[$"/srv/seedings/{hash}.mkv"] = new FileStamp(new FileId(3, inode), 1, 3 * Gb);
    }

    [Fact]
    public async Task ATorrentStillInARadarrOrSonarrQueueIsNotCleanup()
    {
        AddCleanupTorrent("aaaa", 11);
        AddCleanupTorrent("bbbb", 12);
        AddCleanupTorrent("cccc", 13);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(
            kind == ArrKind.Radarr ? [new ArrQueueItem { Id = 1, DownloadId = "AAAA" }, null] : [new ArrQueueItem { Id = 2, DownloadId = "BBBB" }]);

        var overview = await ScanAsync();

        Assert.Equal("torrent:cccc", Assert.Single(overview.Cleanup.Torrents).Key);
        Assert.Equal(["cccc"], _service.LastScan!.Torrents.Keys);
    }

    [Fact]
    public async Task AnUnreadableQueueMeansNoCleanupTorrents()
    {
        AddCleanupTorrent("aaaa", 11);
        _arr.Queue = kind => kind == ArrKind.Sonarr
            ? Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable))
            : Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);

        var overview = await ScanAsync();

        Assert.Empty(overview.Cleanup.Torrents);
        Assert.Empty(_service.LastScan!.Torrents);
        Assert.Equal("Unreachable", overview.Errors.Sonarr);
    }

    [Fact]
    public async Task ASeriesDuplicateNeedsAKnownEpisodeWithTheSameCode()
    {
        AddSeries("continuing");
        _probe.Files[SeriesFolder + "/Serie.s01e02.720p.mkv"] = new FileStamp(new FileId(2, 90), 1, Gb);
        _probe.Files[SeriesFolder + "/Serie.S04E01.mkv"] = new FileStamp(new FileId(2, 91), 1, Gb);
        _probe.Files[SeriesFolder + "/Making of.mkv"] = new FileStamp(new FileId(2, 92), 1, Gb);

        var overview = await ScanAsync();

        Assert.Equal(SeriesFolder + "/Serie.s01e02.720p.mkv", Assert.Single(overview.Cleanup.Duplicates).Path);
    }

    [Theory]
    [InlineData("Extras")]
    [InlineData("featurettes")]
    [InlineData("Behind The Scenes")]
    [InlineData("deleted scenes")]
    [InlineData("Interviews")]
    [InlineData("scenes")]
    [InlineData("Shorts")]
    [InlineData("trailers")]
    [InlineData("Other")]
    [InlineData("samples")]
    public async Task AMovieExtraIsNeverADuplicate(string folder)
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        _probe.Files[$"{MovieFolder}/{folder}/Bonus.mkv"] = new FileStamp(new FileId(1, 98), 1, 2 * Gb);
        _probe.Files[MovieFolder + "/Coco.old.mkv"] = new FileStamp(new FileId(1, 99), 1, 5 * Gb);

        var overview = await ScanAsync();

        Assert.Equal(MovieFolder + "/Coco.old.mkv", Assert.Single(overview.Cleanup.Duplicates).Path);
    }

    [Fact]
    public async Task RowsDoneAfterTheScanAreHiddenUntilTheNextOne()
    {
        AddMovie(12, 6 * Gb, Now.AddMonths(-8));
        AddCleanupTorrent("aaaa", 11);
        _probe.Files["/srv/downloads/Lost.mkv"] = new FileStamp(new FileId(3, 2), 1, 2 * Gb);
        var before = await ScanAsync();
        Assert.Equal((1, 1, 1), (before.Delete.Count, before.Cleanup.Torrents.Count, before.Cleanup.Orphans.Count));

        _time.Advance(TimeSpan.FromMinutes(1));
        _service.Start(SpaceKinds.Movie, "movie:12");
        _service.Start(SpaceKinds.AllTorrents, SpaceService.AllTorrentsKey);
        _service.Start(SpaceKinds.Orphan, before.Cleanup.Orphans[0].Key);
        await _service.DrainAsync(CancellationToken.None);
        Assert.All((await _service.OverviewAsync(_admin.Id, CancellationToken.None)).Operations, o => Assert.Equal(SpaceOperationStates.Done, o.State));

        var after = await _service.OverviewAsync(_admin.Id, CancellationToken.None);
        Assert.Empty(after.Delete);
        Assert.Empty(after.Cleanup.Torrents);
        Assert.Empty(after.Cleanup.Orphans);

        // Il film è ancora in Radarr (finto): il calcolo dopo lo rimostra.
        _time.Advance(TimeSpan.FromMinutes(1));
        Assert.Single((await ScanAsync()).Delete);
    }

    [Fact]
    public async Task UnseenTorrentFilesMeanNoOrphans()
    {
        // qBittorrent dice un percorso che stat non vede: il legame torrent -> file non è affidabile.
        _qbit.Torrents.Add(new QbitTorrent { Hash = "t1", Name = "Old", Size = 3 * Gb, Progress = 1, Tracker = "https://tracker.example/a", SavePath = "/data/torrents" });
        _qbit.Files["t1"] = [new QbitFile { Name = "Old.mkv", Size = 3 * Gb }];
        _probe.Files["/srv/seedings/Old.mkv"] = new FileStamp(new FileId(3, 1), 1, 3 * Gb);

        var overview = await ScanAsync();

        Assert.Empty(overview.Cleanup.Orphans);
    }
}
