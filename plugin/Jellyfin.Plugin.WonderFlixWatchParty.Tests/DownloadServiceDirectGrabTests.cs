using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Un torrent messo da noi direttamente in qBittorrent: il giro lo importa per cartella quando finisce, e non è "senza titolo".</summary>
public sealed class DownloadServiceDirectGrabTests : IDisposable
{
    private const string Hash = "0123456789abcdef0123456789abcdef01234567";

    private static readonly DateTimeOffset T0 = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeQbitClient _qbit = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    public DownloadServiceDirectGrabTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([Movie(12, title: "Animals", year: 2025, runtime: 106)]);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3)]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 3, Priority = 10 }]);
        _arr.ManualImportFolderItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [new ArrManualImportItem { Path = "/dl/Animals/Animals.mkv", Movie = new ArrFileRef { Id = 12 }, Quality = System.Text.Json.JsonDocument.Parse("{}").RootElement, Size = Gb }]);
        _service = new(_arr, new FakeArrSettings(), new FakeDownloadSettings(), Store(), _time, NullLogger<DownloadService>.Instance, null, _qbit) { Pause = TimeSpan.Zero };

        // Il film è in download da un'ora, da un torrent nostro.
        var book = new DownloadBook();
        book.Put(new DownloadEntry
        {
            Key = "movie:12",
            Kind = DownloadKinds.Movie,
            Title = "Animals (2025)",
            State = DownloadStates.Downloading,
            AvailableSince = T0,
            LastSearchAt = T0 - TimeSpan.FromHours(1),
            DirectHash = Hash,
        });
        book.DirectGrabs[Hash] = "movie:12";
        Store().Save(book);
    }

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private void Torrent(double progress) =>
        _qbit.Torrents.Add(new QbitTorrent { Hash = Hash.ToUpperInvariant(), Name = "Animals", Progress = progress, ContentPath = "/dl/Animals" });

    [Fact]
    public async Task DirectGrabImportedWhenComplete()
    {
        Torrent(1);

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal([(ArrKind.Radarr, "/dl/Animals")], _arr.ManualImportFolderReadCalls);
        Assert.Equal(["/dl/Animals/Animals.mkv"], Assert.Single(_arr.ManualImportCalls).Items.Select(i => i.Path));
        Assert.Equal([true], _arr.ManualImportCopies);
        var saved = Store().Load();
        var entry = saved.Get("movie:12")!;
        Assert.Null(entry.DirectHash);
        Assert.Equal(DownloadStates.Downloading, entry.State);
        Assert.Equal(T0, entry.LastSearchAt);

        // Il torrent c'è ancora (semina): resta fuori dai download senza titolo.
        Assert.Equal("movie:12", saved.DirectGrabs[Hash]);
        Assert.Empty(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task DirectGrabStillDownloadingIsLeftAlone()
    {
        Torrent(0.4);

        await _service.RunCycleAsync(CancellationToken.None);

        // Più di un giro senza coda né file: per un torrent nostro non vuol dire sparito.
        Assert.Empty(_arr.ManualImportCalls);
        Assert.Empty(_arr.SearchReleaseCalls);
        var entry = Store().Load().Get("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, Hash), (entry.State, entry.DirectHash));
    }

    [Fact]
    public async Task DirectGrabGoneIsSearchedAgain()
    {
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(_arr.ManualImportCalls);
        Assert.Single(_arr.SearchReleaseCalls);
        var saved = Store().Load();
        Assert.Empty(saved.DirectGrabs);
        Assert.Null(saved.Get("movie:12")!.DirectHash);
    }

    [Fact]
    public async Task QbitDownKeepsTheDirectGrab()
    {
        _qbit.Fail = QbitError.Unreachable;

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(_arr.SearchReleaseCalls);
        var saved = Store().Load();
        Assert.Equal(Hash, saved.Get("movie:12")!.DirectHash);
        Assert.Equal("movie:12", saved.DirectGrabs[Hash]);
    }

    [Fact]
    public async Task DirectGrabNotListedAsUnknown()
    {
        IReadOnlyList<ArrQueueItem?> unknown =
        [
            new ArrQueueItem { Id = 1, DownloadId = Hash.ToUpperInvariant(), Title = "Animals", TrackedDownloadState = "importBlocked", TrackedDownloadStatus = "warning" },
            new ArrQueueItem { Id = 2, DownloadId = "OTHER", Title = "Altro", TrackedDownloadState = "importBlocked", TrackedDownloadStatus = "warning" },
        ];
        _arr.UnknownQueue = _ => Task.FromResult(unknown);

        var listed = (await _service.OverviewAsync(CancellationToken.None)).Unknown;

        Assert.All(listed, d => Assert.Equal("OTHER", d.DownloadId));
        Assert.NotEmpty(listed);
        Assert.Equal(BlockedOutcome.Changed, await _service.RemoveUnknownAsync("Radarr", Hash.ToUpperInvariant()));
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }
}
