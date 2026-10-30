using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Space.SpaceService;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceOperationsTests : IDisposable
{
    private const string Hash = "h1";
    private const string MediaPath = "/srv/media/Coco.mkv";
    private const string TorrentPath = "/srv/downloads/Coco.mkv";
    private const string QuotaPath = "/srv/quota.txt";
    private const string OrphanKey = "file:0123456789abcdef";
    private const string DuplicateKey = "file:fedcba9876543210";
    private const string DuplicatePath = "/srv/media/Coco.old.mkv";
    private const string LeftoverKey = "file:1111222233334444";
    private const string LeftoverPath = "/srv/downloads/old/Leftover.mkv";
    private const long Size = 6_000_000_000;
    private static readonly FileId CocoId = new(16673, 31119496);

    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeArrClient _arr = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeQbitClient _qbit = new();
    private readonly FakeFileProbe _probe = new();
    private readonly FakeLibraryRefresh _library = new();
    private readonly FakeServer _server = new();
    private readonly FakeSpaceSettings _settings = new() { QbitUrl = "http://127.0.0.1:17541", QuotaFile = QuotaPath };
    private readonly List<string> _calls = [];
    private readonly QbitTorrent _torrent = new()
    {
        Hash = Hash, Name = "Coco.2017.1080p", Size = Size, Progress = 1, Ratio = 0.5, SeedingTime = 3600,
        Tracker = "https://tracker.example/announce", SavePath = "/srv/downloads",
    };

    private readonly SpaceService _service;

    public SpaceOperationsTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
            [new RadarrMovie { Id = 12, TmdbId = 354912, Title = "Coco", Path = "/srv/media", MovieFile = new ArrFileRef { Id = 7, Path = MediaPath, Size = Size } }]);
        _arr.Queue = kind =>
        {
            _calls.Add($"Queue:{kind}");
            return Task.FromResult<IReadOnlyList<ArrQueueItem?>>([new ArrQueueItem { Id = 3, MovieId = 12 }, new ArrQueueItem { Id = 4, MovieId = 13 }, null]);
        };
        _arr.DeleteMovie = id =>
        {
            _calls.Add($"DeleteMovie:{id}");
            return Task.CompletedTask;
        };
        _qbit.OnDelete = hashes => _calls.Add("QbitDelete:" + string.Join(",", hashes));
        _seerr.OnCall = _calls.Add;
        _library.OnRefresh = () => _calls.Add("Refresh");

        _probe.Files[MediaPath] = new FileStamp(CocoId, 2, Size);
        _probe.Files[TorrentPath] = new FileStamp(CocoId, 2, Size);
        _probe.Texts[QuotaPath] = "/dev/sds1 3000 9000 9000";
        _qbit.Torrents.Add(_torrent);
        _qbit.Files[Hash] = [new QbitFile { Name = "Coco.mkv", Size = Size }];
        _seerr.MediaIds[("movie", 354912)] = 77;

        _service = Service();
        _service.LastScan = Scan();
    }

    public void Dispose() => _folder.Dispose();

    private SpaceService Service() => new(
        _arr,
        _seerr,
        new FakeSeerrSettings(),
        _qbit,
        _probe,
        _library,
        _settings,
        new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance),
        new FakeViewingFacts(),
        new FakeSeriesIndex(),
        TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time)),
        _server,
        _time,
        NullLogger<SpaceService>.Instance);

    private static SpaceScan Scan() => new()
    {
        Titles = new Dictionary<string, ScanTitle>
        {
            ["movie:12"] = new("Coco", 354912, "/srv/media", [new FileFact(MediaPath, CocoId, 2, Size)], [Hash]),
            ["season:5:2"] = new("Serie - Stagione 2", 1399, "/srv/tv/Serie", [], []),
        },
        Files = new Dictionary<string, ScanFile>
        {
            [OrphanKey] = new("/etc/passwd", SpaceKinds.Orphan, 1_000),
            [DuplicateKey] = new(DuplicatePath, SpaceKinds.Duplicate, 2_000, "movie:12"),
            [LeftoverKey] = new(LeftoverPath, SpaceKinds.Orphan, 2_000),
        },
        Torrents = new Dictionary<string, TorrentFacts>
        {
            [Hash] = new(Hash, "Coco.2017.1080p", "tracker.example", Size, 1, 0.5, 3600),
        },
    };

    private async Task<SpaceOperationDto> RunAsync(string kind, string key)
    {
        var (outcome, id) = _service.Start(kind, key);
        Assert.Equal(StartOutcome.Started, outcome);
        await _service.DrainAsync(CancellationToken.None);
        return _service.Operation(id!)!;
    }

    private static SpaceStepDto Step(SpaceOperationDto op, string name) => op.Steps.Single(s => s.Name == name);

    private void Protect(TimeSpan seeding)
    {
        _torrent.Tracker = "https://itatorrents.xyz/announce/abc";
        _torrent.Ratio = 1;
        _torrent.SeedingTime = (long)seeding.TotalSeconds;
    }

    [Fact]
    public async Task AMovieRunsAllStepsInOrder()
    {
        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal(["Queue:Radarr", "DeleteMovie:12", "QbitDelete:h1", "FindMediaId", "DeleteMedia", "Refresh"], _calls);
        Assert.Equal((ArrKind.Radarr, 3, false, false), Assert.Single(_arr.RemoveFromQueueCalls));
        Assert.Equal(("movie", 354912), Assert.Single(_seerr.FindMediaCalls));
        Assert.Equal(77, Assert.Single(_seerr.DeletedMedia));
        Assert.Equal(
            [SpaceSteps.FindTorrents, SpaceSteps.RemoveFromQueue, SpaceSteps.DeleteFromRadarr, SpaceSteps.RemoveTorrents,
                SpaceSteps.RemoveFromSeerr, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota],
            op.Steps.Select(s => s.Name));
        Assert.All(op.Steps, s => Assert.Equal(SpaceStepStates.Done, s.State));
        Assert.Equal(SpaceOperationStates.Done, op.State);
        Assert.Equal(_time.GetUtcNow(), op.EndedAt);
        Assert.Equal(Size, op.EstimatedFreedBytes);
        Assert.Equal(1, Step(op, SpaceSteps.RemoveTorrents).Done);
        Assert.True(_qbit.DeleteFiles[Hash]);
    }

    // Un altro torrent sullo stesso percorso del film (cross-seed), protetto o no.
    private void CrossSeed(string hash, bool protect)
    {
        _qbit.Torrents.Add(new QbitTorrent
        {
            Hash = hash, Name = "Coco.cross", Size = Size, Progress = 1, SavePath = "/srv/downloads",
            Ratio = protect ? 1 : 0.5,
            SeedingTime = (long)(protect ? TimeSpan.FromDays(29) : TimeSpan.FromHours(1)).TotalSeconds,
            Tracker = protect ? "https://itatorrents.xyz/announce/x" : "https://tracker.example/announce",
        });
        _qbit.Files[hash] = [new QbitFile { Name = "Coco.mkv", Size = Size }];
    }

    [Fact]
    public async Task ACrossSeedWithAProtectedTorrentKeepsTheDataUntilItsSeedEnds()
    {
        CrossSeed("h2", protect: true);

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal([Hash], Assert.Single(_qbit.Deleted));
        Assert.False(_qbit.DeleteFiles[Hash]);
        Assert.Equal("h2", Assert.Single(_service.Read(b => b.Pending.ToList())).Hash);
        Assert.Equal((0L, Size), (op.EstimatedFreedBytes, op.PendingBytes));

        _time.Advance(TimeSpan.FromDays(1));
        _qbit.Torrents.Single(t => t.Hash == "h2").SeedingTime = (long)TimeSpan.FromDays(30).TotalSeconds;
        await _service.CheckPendingAsync(CancellationToken.None);

        Assert.True(_qbit.DeleteFiles["h2"]);
    }

    [Fact]
    public async Task APendingTorrentSharingItsPathWithOneThatStaysGoesWithoutFiles()
    {
        Protect(TimeSpan.FromDays(29));
        await RunAsync(SpaceKinds.Movie, "movie:12");
        CrossSeed("h3", protect: false);

        _time.Advance(TimeSpan.FromDays(1));
        _torrent.SeedingTime = (long)TimeSpan.FromDays(30).TotalSeconds;
        await _service.CheckPendingAsync(CancellationToken.None);

        Assert.False(_qbit.DeleteFiles[Hash]);
        Assert.False(_qbit.DeleteFiles.ContainsKey("h3"));
        Assert.Equal(0, Assert.Single(_service.Read(b => b.Operations.Where(o => o.Auto).ToList())).EstimatedFreedBytes);
    }

    private void ScanWithTorrent(string hash)
    {
        var scan = Scan();
        _service.LastScan = scan with
        {
            Torrents = new Dictionary<string, TorrentFacts>(scan.Torrents) { [hash] = new(hash, "Coco.cross", "tracker.example", Size, 1, 0.5, 3600) },
        };
    }

    [Fact]
    public async Task RemovingOneCleanupTorrentOfACrossSeedLeavesTheData()
    {
        MakeTorrentOnly();
        CrossSeed("h2", protect: false);

        var op = await RunAsync(SpaceKinds.Torrent, "torrent:" + Hash);

        Assert.False(_qbit.DeleteFiles[Hash]);
        Assert.False(_qbit.DeleteFiles.ContainsKey("h2"));
        Assert.Equal(0, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task RemovingAllCleanupTorrentsOfACrossSeedTakesTheData()
    {
        MakeTorrentOnly();
        CrossSeed("h2", protect: false);
        ScanWithTorrent("h2");

        var op = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        Assert.True(_qbit.DeleteFiles[Hash]);
        Assert.True(_qbit.DeleteFiles["h2"]);
        Assert.Equal(Size, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task RemovingAllCleanupTorrentsLeavesTheDataToOneStillInSeed()
    {
        MakeTorrentOnly();
        CrossSeed("h2", protect: true);
        ScanWithTorrent("h2");

        var op = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        Assert.False(_qbit.DeleteFiles[Hash]);
        Assert.False(_qbit.DeleteFiles.ContainsKey("h2"));
        Assert.Equal(0, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task AProtectedTorrentGoesPending()
    {
        Protect(TimeSpan.FromDays(29));

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Empty(_qbit.Deleted);
        var pending = Assert.Single(_service.Read(b => b.Pending.ToList()));
        Assert.Equal((Hash, "Coco", "itatorrents.xyz", Size), (pending.Hash, pending.Title, pending.Tracker, pending.SizeBytes));
        Assert.Equal(_time.GetUtcNow().AddDays(1), pending.ExpectedAt);
        var step = Step(op, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Done, 0, 1), (step.State, step.Done, step.Waiting));
        Assert.Equal(Size, op.PendingBytes);
        Assert.Equal(SpaceOperationStates.Done, op.State);
    }

    private Task<SpaceOperationDto> RunWithQbitFailingAfterRadarrAsync()
    {
        _arr.DeleteMovie = _ =>
        {
            _qbit.Fail = QbitError.Unreachable;
            return Task.CompletedTask;
        };
        return RunAsync(SpaceKinds.Movie, "movie:12");
    }

    [Fact]
    public async Task QbitDownStopsAfterRadarr()
    {
        var op = await RunWithQbitFailingAfterRadarrAsync();

        Assert.Equal(SpaceStepStates.Done, Step(op, SpaceSteps.DeleteFromRadarr).State);
        var torrents = Step(op, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Failed, SpaceDetails.Unreachable), (torrents.State, torrents.Detail));
        Assert.All(
            [SpaceSteps.RemoveFromSeerr, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota],
            name => Assert.Equal(SpaceStepStates.NotDone, Step(op, name).State));
        Assert.Equal(SpaceOperationStates.Failed, op.State);
        Assert.NotNull(op.EndedAt);
        Assert.Empty(_seerr.Calls);
        Assert.Equal(0, _library.Calls);
    }

    [Fact]
    public async Task RetryingSkipsWhatIsGone()
    {
        await RunWithQbitFailingAfterRadarrAsync();

        // Radarr ha già tolto il film e il suo file: resta solo il percorso del torrent.
        _qbit.Fail = null;
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        _arr.DeleteMovie = _ => throw new ArrException(ArrError.Unreachable, status: 404);
        _probe.Files.Remove(MediaPath);
        _probe.Files[TorrentPath] = new FileStamp(CocoId, 1, Size);

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        var radarr = Step(op, SpaceSteps.DeleteFromRadarr);
        Assert.Equal((SpaceStepStates.Skipped, SpaceDetails.Gone), (radarr.State, radarr.Detail));
        Assert.Equal([Hash], Assert.Single(_qbit.Deleted));
        Assert.Equal(SpaceOperationStates.Done, op.State);
    }

    [Fact]
    public void ASecondStartOnTheSameKeyIsBusy()
    {
        Assert.Equal(StartOutcome.Started, _service.Start(SpaceKinds.Movie, "movie:12").Outcome);
        Assert.Equal((StartOutcome.Busy, null), _service.Start(SpaceKinds.Movie, "movie:12"));
    }

    [Fact]
    public void AnUnknownKeyIsUnknown()
    {
        Assert.Equal((StartOutcome.Unknown, null), _service.Start(SpaceKinds.Movie, "movie:99"));
        Assert.Equal(StartOutcome.Unknown, _service.Start(SpaceKinds.Duplicate, OrphanKey).Outcome);
        Assert.Equal(StartOutcome.NotReady, Service().Start(SpaceKinds.Movie, "movie:12").Outcome);
    }

    [Theory]
    [InlineData("Film", "movie:12")]
    [InlineData(SpaceKinds.Movie, "series:12")]
    [InlineData(SpaceKinds.Movie, "movie:0")]
    [InlineData(SpaceKinds.Movie, "movie:12:1")]
    [InlineData(SpaceKinds.Season, "season:5")]
    [InlineData(SpaceKinds.Torrent, "torrent:")]
    [InlineData(SpaceKinds.Orphan, "file:../etc")]
    [InlineData(SpaceKinds.AllTorrents, "torrent:h1")]
    public void AWrongKindOrKeyIsInvalid(string kind, string key) =>
        Assert.Equal((StartOutcome.Invalid, null), _service.Start(kind, key));

    [Fact]
    public async Task ASeasonUnmonitorsAndDeletesItsFiles()
    {
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
        [
            new ArrFile { Id = 21, SeasonNumber = 2, Path = "/srv/tv/Serie/S02E01.mkv" },
            new ArrFile { Id = 11, SeasonNumber = 1, Path = "/srv/tv/Serie/S01E01.mkv" },
            new ArrFile { Id = 22, SeasonNumber = 2, Path = "/srv/tv/Serie/S02E02.mkv" },
        ]);

        var op = await RunAsync(SpaceKinds.Season, "season:5:2");

        Assert.Equal((5, 2, false), Assert.Single(_arr.SetSeasonMonitoredCalls));
        Assert.Equal([21, 22], Assert.Single(_arr.DeleteEpisodeFileCalls));
        Assert.Empty(_arr.DeleteSeriesCalls);
        Assert.Empty(_seerr.Calls);
        Assert.Equal(
            [SpaceSteps.FindTorrents, SpaceSteps.RemoveFromQueue, SpaceSteps.UnmonitorSeason, SpaceSteps.DeleteEpisodeFiles,
                SpaceSteps.RemoveTorrents, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota],
            op.Steps.Select(s => s.Name));
        Assert.Equal(SpaceOperationStates.Done, op.State);
    }

    [Fact]
    public async Task AFileOutsideTheRootsIsNeverDeleted()
    {
        var op = await RunAsync(SpaceKinds.Orphan, OrphanKey);

        var step = Step(op, SpaceSteps.DeleteFile);
        Assert.Equal((SpaceStepStates.Failed, SpaceDetails.Failed), (step.State, step.Detail));
        Assert.Empty(_probe.DeleteCalls);
        Assert.Empty(_probe.Deleted);
        Assert.Equal(SpaceStepStates.NotDone, Step(op, SpaceSteps.ReadQuota).State);
        Assert.Equal(SpaceOperationStates.Failed, op.State);
    }

    private void Library(string? folder, string filePath) =>
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
            [new RadarrMovie { Id = 12, Path = folder, MovieFile = new ArrFileRef { Path = filePath } }]);

    [Fact]
    public async Task ADuplicateGoesOnlyFromItsLiveTitleFolderAndOnlyIfRadarrDoesNotKnowIt()
    {
        Library("/srv/media", DuplicatePath);
        var known = await RunAsync(SpaceKinds.Duplicate, DuplicateKey);

        Library("/srv/media/other", MediaPath);
        var moved = await RunAsync(SpaceKinds.Duplicate, DuplicateKey);

        Assert.Equal(SpaceStepStates.Failed, Step(known, SpaceSteps.DeleteFile).State);
        Assert.Equal(SpaceStepStates.Failed, Step(moved, SpaceSteps.DeleteFile).State);
        Assert.Empty(_probe.DeleteCalls);

        Library("/srv/media", MediaPath);
        var op = await RunAsync(SpaceKinds.Duplicate, DuplicateKey);

        Assert.Equal(SpaceOperationStates.Done, op.State);
        var call = Assert.Single(_probe.DeleteCalls);
        Assert.Equal(DuplicatePath, call.Path);
        Assert.Equal(["/srv/media"], call.Roots);
        Assert.Equal(2_000, op.EstimatedFreedBytes);
    }

    [Theory]
    [InlineData(1, 2_000, true)]
    [InlineData(2, 2_000, false)]
    [InlineData(1, 3_000, false)]
    public async Task AnOrphanGoesFromTheScanFoldersOnlyIfStillTheSameLoneFile(int links, long size, bool deleted)
    {
        _probe.Files[LeftoverPath] = new FileStamp(new FileId(1, 5), links, size);

        var op = await RunAsync(SpaceKinds.Orphan, LeftoverKey);

        Assert.Equal(deleted ? SpaceOperationStates.Done : SpaceOperationStates.Failed, op.State);
        if (deleted)
        {
            var call = Assert.Single(_probe.DeleteCalls);
            Assert.Equal(LeftoverPath, call.Path);
            Assert.Equal(_settings.ScanFolders, call.Roots);
        }
        else
        {
            Assert.Equal(SpaceDetails.Failed, Step(op, SpaceSteps.DeleteFile).Detail);
            Assert.Empty(_probe.DeleteCalls);
        }
    }

    // Il titolo non c'è più: il file del torrent resta l'unico collegamento.
    private void MakeTorrentOnly()
    {
        _probe.Files.Remove(MediaPath);
        _probe.Files[TorrentPath] = new FileStamp(CocoId, 1, Size);
    }

    [Fact]
    public async Task ACleanupTorrentNowInTheLibraryOrStillDownloadingStays()
    {
        // Il file del torrent ha di nuovo un hardlink in libreria (Radarr l'ha importato dopo il calcolo).
        var single = await RunAsync(SpaceKinds.Torrent, "torrent:" + Hash);
        var all = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        MakeTorrentOnly();
        _torrent.Progress = 0.5;
        var downloading = await RunAsync(SpaceKinds.Torrent, "torrent:" + Hash);

        var step = Step(single, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Skipped, SpaceDetails.Gone), (step.State, step.Detail));
        Assert.Equal(0, Step(all, SpaceSteps.RemoveTorrents).Done);
        Assert.Equal(SpaceDetails.SeedRule, Step(downloading, SpaceSteps.RemoveTorrents).Detail);
        Assert.Empty(_qbit.Deleted);
    }

    [Theory]
    [InlineData("h9", Size)]
    [InlineData(Hash, Size + 1)]
    public async Task AReusedInodeIsNeverRemovedOnRetry(string hash, long size)
    {
        // Radarr ha già tolto il film (un file copiato, senza hardlink) e il torrent di prima non c'è più; quell'inode ora
        // è di un download nuovo: in un altro torrent, o con una dimensione diversa.
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        _probe.Files.Remove(MediaPath);
        _probe.Files.Remove(TorrentPath);
        _probe.Files["/srv/downloads/New.mkv"] = new FileStamp(CocoId, 1, size);
        _qbit.Torrents.Clear();
        _qbit.Torrents.Add(new QbitTorrent { Hash = hash, Name = "New", Size = size, Progress = 1, SavePath = "/srv/downloads", Tracker = "https://tracker.example/a" });
        _qbit.Files[hash] = [new QbitFile { Name = "New.mkv", Size = size }];

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Empty(_qbit.Deleted);
        Assert.Empty(_service.Read(b => b.Pending.ToList()));
        var step = Step(op, SpaceSteps.RemoveTorrents);
        Assert.Equal((0, 0), (step.Done, step.Waiting));
    }

    [Fact]
    public async Task APackWithAnotherTitleInTheLibraryStays()
    {
        _qbit.Torrents.Clear();
        _qbit.Torrents.Add(new QbitTorrent { Hash = "pack", Name = "Pack", Size = 2 * Size, Progress = 1, SavePath = "/srv/downloads", Tracker = "https://tracker.example/a" });
        _qbit.Files["pack"] = [new QbitFile { Name = "Coco.mkv", Size = Size }, new QbitFile { Name = "Other.mkv", Size = Size }];
        _probe.Files["/srv/downloads/Other.mkv"] = new FileStamp(new FileId(16673, 999), 2, Size);

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Empty(_qbit.Deleted);
        Assert.Empty(_service.Read(b => b.Pending.ToList()));
        var step = Step(op, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Done, 0, 0), (step.State, step.Done, step.Waiting));
        Assert.Equal(0, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task AStatTimeoutStopsBeforeRadarr()
    {
        _probe.StatFails = new TimeoutException();

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        var step = Step(op, SpaceSteps.FindTorrents);
        Assert.Equal((SpaceStepStates.Failed, SpaceDetails.Unreachable), (step.State, step.Detail));
        Assert.Empty(_arr.DeleteMovieCalls);
        Assert.Empty(_arr.RemoveFromQueueCalls);
        Assert.Equal(SpaceStepStates.NotDone, Step(op, SpaceSteps.DeleteFromRadarr).State);
        Assert.Equal(SpaceOperationStates.Failed, op.State);
    }

    [Fact]
    public async Task TheQueueKeepsFinishedDownloadsInQbitAndSkipsWhatIsGone()
    {
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(
        [
            new ArrQueueItem { Id = 3, MovieId = 12, Sizeleft = 0 },
            new ArrQueueItem { Id = 5, MovieId = 12, Sizeleft = 100 },
            new ArrQueueItem { Id = 6, MovieId = 12, Sizeleft = 100 },
        ]);
        _arr.RemoveFromQueue = (_, id, _) => id == 5 ? Task.FromException(new ArrException(ArrError.Unreachable, status: 404)) : Task.CompletedTask;

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal(
            [(ArrKind.Radarr, 3, false, false), (ArrKind.Radarr, 5, false, true), (ArrKind.Radarr, 6, false, true)],
            _arr.RemoveFromQueueCalls);
        var step = Step(op, SpaceSteps.RemoveFromQueue);
        Assert.Equal((SpaceStepStates.Done, 2), (step.State, step.Done));
        Assert.Equal(SpaceOperationStates.Done, op.State);
    }

    [Fact]
    public async Task ATorrentStillInMandatorySeedIsSkipped()
    {
        MakeTorrentOnly();
        Protect(TimeSpan.FromDays(3));

        var op = await RunAsync(SpaceKinds.Torrent, "torrent:" + Hash);

        var step = Step(op, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Skipped, SpaceDetails.SeedRule), (step.State, step.Detail));
        Assert.Empty(_qbit.Deleted);
        Assert.Equal(SpaceOperationStates.Done, op.State);
    }

    [Fact]
    public async Task AllTorrentsTakesTheOnesThatCanGoNow()
    {
        MakeTorrentOnly();

        var op =await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        Assert.Equal([Hash], Assert.Single(_qbit.Deleted));
        Assert.Equal(1, Step(op, SpaceSteps.RemoveTorrents).Done);
        Assert.Equal(Size, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task PendingTorrentsGoWhenAllowed()
    {
        Protect(TimeSpan.FromDays(29));
        await RunAsync(SpaceKinds.Movie, "movie:12");
        Assert.Equal(_time.GetUtcNow().AddDays(1), Assert.Single(_service.Read(b => b.Pending.ToList())).ExpectedAt);

        await _service.CheckPendingAsync(CancellationToken.None);
        Assert.Empty(_qbit.Deleted);

        _time.Advance(TimeSpan.FromDays(1));
        _torrent.SeedingTime = (long)TimeSpan.FromDays(30).TotalSeconds;
        await _service.CheckPendingAsync(CancellationToken.None);

        Assert.Equal([Hash], Assert.Single(_qbit.Deleted));
        Assert.Empty(_service.Read(b => b.Pending.ToList()));
        var auto = Assert.Single(_service.Read(b => b.Operations.Where(o => o.Auto).ToList()));
        Assert.Equal((SpaceKinds.Torrent, "torrent:h1", "Coco", SpaceOperationStates.Done), (auto.Kind, auto.Key, auto.Title, auto.State));
        Assert.Equal([SpaceSteps.RemoveTorrents, SpaceSteps.ReadQuota], auto.Steps.Select(s => s.Name));
        Assert.All(auto.Steps, s => Assert.Equal(SpaceStepStates.Done, s.State));
    }

    [Fact]
    public async Task APendingTorrentGoneFromQbitLeavesTheList()
    {
        Protect(TimeSpan.FromDays(29));
        await RunAsync(SpaceKinds.Movie, "movie:12");

        _qbit.Fail = QbitError.Unreachable;
        await _service.CheckPendingAsync(CancellationToken.None);
        Assert.Single(_service.Read(b => b.Pending.ToList()));

        _qbit.Fail = null;
        _qbit.Torrents.Clear();
        await _service.CheckPendingAsync(CancellationToken.None);

        Assert.Empty(_service.Read(b => b.Pending.ToList()));
        Assert.Empty(_qbit.Deleted);
    }

    [Fact]
    public async Task ADropWhileCheckingWins()
    {
        Protect(TimeSpan.FromDays(29));
        await RunAsync(SpaceKinds.Movie, "movie:12");
        _torrent.SeedingTime = (long)TimeSpan.FromDays(30).TotalSeconds;
        _qbit.OnGetTorrents = () => _service.DropPending(Hash);

        await _service.CheckPendingAsync(CancellationToken.None);

        Assert.Empty(_qbit.Deleted);
        Assert.Empty(_service.Read(b => b.Operations.Where(o => o.Auto).ToList()));
    }

    [Fact]
    public async Task QuotaBeforeAndAfterAreRecorded()
    {
        _arr.DeleteMovie = _ =>
        {
            _probe.Texts[QuotaPath] = "/dev/sds1 1000 9000 9000";
            _probe.WriteTimes[QuotaPath] = _time.GetUtcNow();
            return Task.CompletedTask;
        };

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal(3000L * 1024, op.QuotaBeforeBytes);
        Assert.Equal(1000L * 1024, op.QuotaAfterBytes);
    }

    [Fact]
    public async Task AQuotaFileOlderThanTheOperationGivesNoAfter()
    {
        // Il cron riscrive il file ogni 10 minuti: letto subito dopo, è quello di prima.
        _probe.WriteTimes[QuotaPath] = _time.GetUtcNow().AddMinutes(-3);

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal(3000L * 1024, op.QuotaBeforeBytes);
        Assert.Null(op.QuotaAfterBytes);
        Assert.Equal(SpaceStepStates.Done, Step(op, SpaceSteps.ReadQuota).State);

        Protect(TimeSpan.FromDays(29));
        _qbit.Torrents.Add(_torrent);
        await RunAsync(SpaceKinds.Movie, "movie:12");
        _time.Advance(TimeSpan.FromDays(1));
        _torrent.SeedingTime = (long)TimeSpan.FromDays(30).TotalSeconds;
        await _service.CheckPendingAsync(CancellationToken.None);

        var auto = Assert.Single(_service.Read(b => b.Operations.Where(o => o.Auto).ToList()));
        Assert.Equal(3000L * 1024, auto.QuotaBeforeBytes);
        Assert.Null(auto.QuotaAfterBytes);
    }

    [Fact]
    public async Task AQueuedDownloadIsNotRemovedByCleanup()
    {
        MakeTorrentOnly();
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([new ArrQueueItem { Id = 3, DownloadId = Hash.ToUpperInvariant() }]);

        var single = await RunAsync(SpaceKinds.Torrent, "torrent:" + Hash);
        var all = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));
        var unreadable = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

        Assert.Equal(SpaceDetails.Gone, Step(single, SpaceSteps.RemoveTorrents).Detail);
        Assert.Equal(0, Step(all, SpaceSteps.RemoveTorrents).Done);
        var step = Step(unreadable, SpaceSteps.RemoveTorrents);
        Assert.Equal((SpaceStepStates.Failed, SpaceDetails.Unreachable), (step.State, step.Detail));
        Assert.Empty(_qbit.Deleted);
    }

    [Fact]
    public void AllTorrentsHasADescriptiveTitle()
    {
        var (_, id) = _service.Start(SpaceKinds.AllTorrents, AllTorrentsKey);

        Assert.Equal("Pulizia: torrent senza libreria", _service.Operation(id!)!.Title);
    }

    [Fact]
    public void AnInterruptedOperationFailsOnReload()
    {
        var (_, id) = _service.Start(SpaceKinds.Movie, "movie:12");

        var reloaded = Service();
        reloaded.LastScan = Scan();

        var op = reloaded.Operation(id!)!;
        Assert.Equal(SpaceOperationStates.Failed, op.State);
        Assert.All(op.Steps, s => Assert.Equal(SpaceStepStates.NotDone, s.State));
        Assert.Equal(StartOutcome.Started, reloaded.Start(SpaceKinds.Movie, "movie:12").Outcome);
    }

    [Fact]
    public async Task KeptTitlesAndDroppedPendingAreSaved()
    {
        Protect(TimeSpan.FromDays(29));
        await RunAsync(SpaceKinds.Movie, "movie:12");
        _service.Keep("series:5", "Serie");

        Assert.True(_service.DropPending(Hash));
        Assert.False(_service.DropPending(Hash));
        var reloaded = Service();
        Assert.True(reloaded.Read(b => b.IsKept("series:5")));
        Assert.Empty(reloaded.Read(b => b.Pending.ToList()));

        reloaded.Unkeep("series:5");
        Assert.False(Service().Read(b => b.IsKept("series:5")));
    }
}
