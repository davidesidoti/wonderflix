using System.Text.Json;
using Jellyfin.Extensions.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SpaceLightenStatusTests : IDisposable
{
    private const long Gb = 1_000_000_000;

    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeServer _server = new();
    private readonly FakeArrClient _arr = new();
    private readonly DownloadService _downloads;
    private readonly SpaceService _service;
    private readonly Guid _admin;

    private List<ArrQueueItem?> _radarrQueue = [];
    private List<ArrQueueItem?> _sonarrQueue = [];
    private long _movieFileSize = 12 * Gb;

    public SpaceLightenStatusTests()
    {
        _admin = _server.AddUser("Admin", isAdmin: true).Id;
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : _sonarrQueue);
        _arr.MovieById = id => Task.FromResult(new RadarrMovie { Id = id, MovieFile = new ArrFileRef { Id = 1, Size = _movieFileSize } });
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
        [
            new ArrFile { Id = 21, SeasonNumber = 2, Size = 6 * Gb },
            new ArrFile { Id = 22, SeasonNumber = 2, Size = 6 * Gb },
            new ArrFile { Id = 31, SeasonNumber = 3, Size = 1 * Gb },
        ]);

        // Niente Load(): i test scrivono downloads.json prima che il servizio lo legga.
        _downloads = TestDownloads.Create(_arr, _time, _folder.DownloadsFile);
        _service = new SpaceService(
            _arr,
            new FakeSeerrClient(),
            new FakeSeerrSettings(),
            new FakeQbitClient(),
            new FakeFileProbe(),
            new FakeLibraryRefresh(),
            new FakeSpaceSettings(),
            new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance),
            new FakeViewingFacts(),
            new FakeSeriesIndex(),
            TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time)),
            _server,
            _downloads,
            _time,
            NullLogger<SpaceService>.Instance)
        {
            LastScan = new SpaceScan
            {
                Lighten = [Row("movie:12", SpaceKinds.Movie, null), Row("season:5:2", SpaceKinds.Season, 2), Row("movie:13", SpaceKinds.Movie, null)],
            },
        };
    }

    public void Dispose() => _folder.Dispose();

    private DateTimeOffset Now => _time.GetUtcNow();

    private static ScanRow<SpaceLightenDto> Row(string key, string kind, int? season) =>
        new(new SpaceLightenDto(key, kind, "Titolo", season, null, null, 12 * Gb, 6 * Gb, 6.5, null), [key], []);

    private void Lightened(string key, DateTimeOffset at)
    {
        var store = new DownloadStore(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);
        var book = store.Load();
        book.MarkLightened(key, at);
        store.Save(book);
    }

    private static ArrQueueItem Item(string state, long size, long left, int? movieId = null, int? seriesId = null, int? season = null) =>
        new() { MovieId = movieId, SeriesId = seriesId, SeasonNumber = season, Size = size, Sizeleft = left, TrackedDownloadState = state };

    private async Task<SpaceLightenDownloadDto?> DownloadOf(string key) =>
        Assert.Single((await _service.OverviewAsync(_admin, CancellationToken.None)).Lighten, r => r.Key == key).Download;

    [Fact]
    public async Task ADownloadingMovieShowsProgress()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _radarrQueue = [Item("downloading", 4 * Gb, 1 * Gb, movieId: 12), Item("downloading", 9 * Gb, 9 * Gb, movieId: 99)];

        Assert.Equal(new SpaceLightenDownloadDto(SpaceLightenStates.Downloading, 0.75, 1 * Gb), await DownloadOf("movie:12"));
        Assert.Null(await DownloadOf("movie:13"));
    }

    [Fact]
    public async Task ImportPendingIsImporting()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _radarrQueue = [Item("importPending", 4 * Gb, 0, movieId: 12)];

        Assert.Equal(SpaceLightenStates.Importing, (await DownloadOf("movie:12"))!.State);
    }

    [Fact]
    public async Task AFailedQueueItemIsFailed()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _radarrQueue = [Item("failedPending", 4 * Gb, 2 * Gb, movieId: 12)];

        Assert.Equal(SpaceLightenStates.Failed, (await DownloadOf("movie:12"))!.State);
    }

    [Fact]
    public async Task AnImportedLighterFileHidesTheRow()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _movieFileSize = 3 * Gb;

        var overview = await _service.OverviewAsync(_admin, CancellationToken.None);

        Assert.DoesNotContain(overview.Lighten, r => r.Key == "movie:12");
        Assert.False(_downloads.LightenedKeys().ContainsKey("movie:12"));
        Assert.False(new DownloadStore(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance).Load().Lightened.ContainsKey("movie:12"));

        // Fino al prossimo calcolo la riga resta nascosta, anche senza la chiave.
        Assert.DoesNotContain((await _service.OverviewAsync(_admin, CancellationToken.None)).Lighten, r => r.Key == "movie:12");
    }

    [Fact]
    public async Task ARecentGrabNotYetQueuedIsDownloading()
    {
        Lightened("movie:12", Now.AddMinutes(-5));

        Assert.Equal(new SpaceLightenDownloadDto(SpaceLightenStates.Downloading, 0, 0), await DownloadOf("movie:12"));
    }

    [Fact]
    public async Task AnOldGrabWithoutQueueIsFailed()
    {
        Lightened("movie:12", Now.AddMinutes(-20));

        Assert.Equal(new SpaceLightenDownloadDto(SpaceLightenStates.Failed, 0, 0), await DownloadOf("movie:12"));
        Assert.True(_downloads.LightenedKeys().ContainsKey("movie:12"));
    }

    [Fact]
    public async Task ASeasonWithSeveralQueueItemsSumsProgress()
    {
        Lightened("season:5:2", Now.AddHours(-1));
        _sonarrQueue =
        [
            Item("importPending", 2 * Gb, 0, seriesId: 5, season: 2),
            Item("downloading", 2 * Gb, 1 * Gb, seriesId: 5, season: 2),
            Item("downloading", 10 * Gb, 10 * Gb, seriesId: 5, season: 3),
        ];

        Assert.Equal(new SpaceLightenDownloadDto(SpaceLightenStates.Downloading, 0.75, 1 * Gb), await DownloadOf("season:5:2"));
        Assert.Empty(_arr.QueueCalls.Where(k => k == ArrKind.Radarr));
    }

    [Fact]
    public async Task AnImportedSeasonHidesTheRow()
    {
        Lightened("season:5:2", Now.AddHours(-1));
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
            [new ArrFile { Id = 21, SeasonNumber = 2, Size = 5 * Gb }, new ArrFile { Id = 31, SeasonNumber = 3, Size = 20 * Gb }]);

        Assert.DoesNotContain((await _service.OverviewAsync(_admin, CancellationToken.None)).Lighten, r => r.Key == "season:5:2");
        Assert.Empty(_downloads.LightenedKeys());
    }

    [Fact]
    public async Task AnUnreachableServiceKeepsTheLastStatus()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _radarrQueue = [Item("downloading", 4 * Gb, 1 * Gb, movieId: 12)];
        var before = await DownloadOf("movie:12");

        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));
        _time.Advance(TimeSpan.FromHours(1));

        Assert.Equal(before, await DownloadOf("movie:12"));
        Assert.True(_downloads.LightenedKeys().ContainsKey("movie:12"));
    }

    [Fact]
    public async Task AnUnreachableServiceWithoutAStatusIsNull()
    {
        Lightened("movie:12", Now.AddHours(-1));
        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));

        Assert.Null(await DownloadOf("movie:12"));
    }

    [Fact]
    public async Task KeysOlderThanSevenDaysAreForgotten()
    {
        Lightened("movie:12", Now.AddDays(-8));
        _radarrQueue = [Item("downloading", 4 * Gb, 1 * Gb, movieId: 12)];

        Assert.Null(await DownloadOf("movie:12"));
        Assert.Empty(_downloads.LightenedKeys());
        Assert.Empty(_arr.QueueCalls);
    }

    [Fact]
    public async Task RowsWithoutLightenHaveNoDownload()
    {
        // Una chiave Alleggerisci di un titolo che non è in Alleggerire non costa letture.
        Lightened("movie:77", Now.AddHours(-1));

        var overview = await _service.OverviewAsync(_admin, CancellationToken.None);

        Assert.All(overview.Lighten, r => Assert.Null(r.Download));
        Assert.Empty(_arr.QueueCalls);
        Assert.Contains("\"Download\":null", JsonSerializer.Serialize(overview.Lighten[0], JsonDefaults.PascalCaseOptions), StringComparison.Ordinal);
    }
}
