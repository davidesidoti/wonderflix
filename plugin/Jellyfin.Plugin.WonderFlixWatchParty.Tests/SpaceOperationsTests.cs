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
    private const long Size = 6_000_000_000;
    private static readonly FileId CocoId = new(16673, 31119496);

    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeArrClient _arr = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeQbitClient _qbit = new();
    private readonly FakeFileProbe _probe = new();
    private readonly FakeLibraryRefresh _library = new();
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
        _time,
        NullLogger<SpaceService>.Instance);

    private static SpaceScan Scan() => new()
    {
        Titles = new Dictionary<string, ScanTitle>
        {
            ["movie:12"] = new("Coco", 354912, "/srv/media", [new FileFact(MediaPath, CocoId, 2, Size)]),
            ["season:5:2"] = new("Serie - Stagione 2", 1399, "/srv/tv/Serie", []),
        },
        Files = new Dictionary<string, ScanFile>
        {
            [OrphanKey] = new("/etc/passwd", SpaceKinds.Orphan, 1_000),
            [DuplicateKey] = new(DuplicatePath, SpaceKinds.Duplicate, 2_000, "movie:12", "/srv/media"),
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
        Assert.Equal((ArrKind.Radarr, 3, false), Assert.Single(_arr.RemoveFromQueueCalls));
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

    [Fact]
    public async Task ADuplicateGoesOnlyFromItsTitleFolderAndOnlyIfRadarrDoesNotKnowIt()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
            [new RadarrMovie { Id = 12, MovieFile = new ArrFileRef { Path = DuplicatePath } }]);

        var known = await RunAsync(SpaceKinds.Duplicate, DuplicateKey);

        Assert.Equal(SpaceStepStates.Failed, Step(known, SpaceSteps.DeleteFile).State);
        Assert.Empty(_probe.DeleteCalls);

        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
            [new RadarrMovie { Id = 12, MovieFile = new ArrFileRef { Path = MediaPath } }]);

        var op = await RunAsync(SpaceKinds.Duplicate, DuplicateKey);

        Assert.Equal(SpaceOperationStates.Done, op.State);
        var call = Assert.Single(_probe.DeleteCalls);
        Assert.Equal(DuplicatePath, call.Path);
        Assert.Equal(["/srv/media"], call.Roots);
        Assert.Equal(2_000, op.EstimatedFreedBytes);
    }

    [Fact]
    public async Task ATorrentStillInMandatorySeedIsSkipped()
    {
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
        var op = await RunAsync(SpaceKinds.AllTorrents, "all-torrents");

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
    public async Task QuotaBeforeAndAfterAreRecorded()
    {
        _arr.DeleteMovie = _ =>
        {
            _probe.Texts[QuotaPath] = "/dev/sds1 1000 9000 9000";
            return Task.CompletedTask;
        };

        var op = await RunAsync(SpaceKinds.Movie, "movie:12");

        Assert.Equal(3000L * 1024, op.QuotaBeforeBytes);
        Assert.Equal(1000L * 1024, op.QuotaAfterBytes);
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
