using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Gli avvisi agli admin dei download (spec V): "serve te" tenuto in pari dopo ogni giro, e lo storico dei fermi.</summary>
public sealed class DownloadAlertsTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 31, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly RecordingPush _push = new();
    private readonly InboxService _inbox;
    private readonly DownloadService _downloads;
    private readonly DownloadsHostedService _hosted;
    private readonly UserRef _admin;
    private List<RadarrMovie?> _movies = [];
    private List<ArrQueueItem?> _queue = [];

    public DownloadAlertsTests()
    {
        _admin = _server.AddUser("Anna", isAdmin: true);
        _server.AddUser("Bruno");
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _queue : []);
        _inbox = TestInbox.Create(_server, _folder, _time, _push);
        var alerts = new AdminAlerts(_inbox, _server, _time, NullLogger<AdminAlerts>.Instance);
        _downloads = TestDownloads.Create(_arr, _time, _folder.DownloadsFile, alerts);
        _hosted = new DownloadsHostedService(_downloads, alerts, _time, NullLogger<DownloadsHostedService>.Instance);
    }

    public void Dispose()
    {
        _hosted.Dispose();
        _folder.Dispose();
    }

    private sealed class RecordingPush : IInboxPush
    {
        public List<(Guid UserId, InboxEntry Entry)> Delivered { get; } = [];

        public void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh) => Delivered.AddRange(fresh);
    }

    // Come i timer in produzione: da un thread senza contesto di sincronizzazione.
    private Task Advance(TimeSpan by) => Task.Run(() => _time.Advance(by));

    private void Blocked()
    {
        _movies = [Movie(12)];
        _queue = [MovieQueue(90, 12, 0, state: "importBlocked")];
    }

    private IReadOnlyList<InboxEntry> Entries() => _inbox.Get(_admin.Id).Entries;

    [Fact]
    public async Task NeedsYouAlerts_OnePerNeedsYouEntry()
    {
        _movies = [Movie(12), Movie(13)];
        _queue = [MovieQueue(90, 12, 0, state: "importBlocked"), MovieQueue(91, 13, 5_000)];
        await _downloads.RunCycleAsync(CancellationToken.None);

        var alert = Assert.Single(_downloads.NeedsYouAlerts());

        Assert.Equal(
            new AdminAlert("download:movie:12", InboxEntryTypes.DownloadNeedsYou, "Dune (2021)", Reason: DownloadReasons.ImportBlocked), alert);
    }

    [Fact]
    public async Task Cycle_SyncsDownloadAlerts()
    {
        await _hosted.StartAsync(CancellationToken.None);
        Blocked();

        await Advance(DownloadService.CycleInterval);

        var entry = Assert.Single(Entries());
        Assert.Equal(("download:movie:12", InboxEntryTypes.DownloadNeedsYou, DownloadReasons.ImportBlocked), (entry.AlertKey, entry.Type, entry.Reason));

        // Risolto: al giro dopo la voce si toglie.
        _queue = [];
        _movies = [Movie(12, hasFile: true)];
        await Advance(DownloadService.CycleInterval);
        Assert.Empty(Entries());
    }

    [Fact]
    public async Task Review_SyncsDownloadAlerts()
    {
        Blocked();
        await _downloads.RunCycleAsync(CancellationToken.None);
        Assert.Empty(Entries());
        await _hosted.StartAsync(CancellationToken.None);

        await Advance(DownloadsHostedService.FirstReviewDelay);

        Assert.Equal("download:movie:12", Assert.Single(Entries()).AlertKey);
    }

    [Fact]
    public async Task Cycle_TwiceSameState_SinglePush()
    {
        await _hosted.StartAsync(CancellationToken.None);
        Blocked();

        await Advance(DownloadService.CycleInterval);
        await Advance(DownloadService.CycleInterval);

        Assert.Single(Entries());
        Assert.Single(_push.Delivered);
    }

    [Fact]
    public async Task RemoveStalled_RaisesHistory()
    {
        _movies = [Movie(12)];
        _queue = [MovieQueue(90, 12, 5_000)];
        await _downloads.RunCycleAsync(CancellationToken.None);

        _time.Advance(DownloadSchedule.StalledAfter);
        await _downloads.RunCycleAsync(CancellationToken.None);

        var entry = Assert.Single(Entries());
        Assert.Equal(($"stalled:movie:12:{_time.GetUtcNow().Ticks}", InboxEntryTypes.DownloadStalled, "Dune (2021)"), (entry.AlertKey, entry.Type, entry.Title));
    }

    [Fact]
    public async Task Start_SyncsStaleAlerts()
    {
        // Una voce di prima del riavvio, per un titolo che non serve più.
        await _inbox.SyncAlertsAsync([_admin.Id], "download:", [new InboxEntry { Type = InboxEntryTypes.DownloadNeedsYou, AlertKey = "download:movie:99", Title = "Old" }]);
        Assert.Single(Entries());

        await _hosted.StartAsync(CancellationToken.None);

        // L'allineamento iniziale gira in sottofondo.
        for (var i = 0; i < 100 && Entries().Count > 0; i++)
        {
            await Task.Delay(50);
        }

        Assert.Empty(Entries());
    }

    [Fact]
    public async Task AdminGrab_NudgesACycle()
    {
        // Il titolo era in "serve te": dopo il grab l'avviso esce con un giro, non dopo 15 minuti.
        _movies = [Movie(12)];
        _queue = [MovieQueue(90, 12, 0, state: "importBlocked")];
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([Release("a", WebDl1080, "WEBDL-1080p", 4, 150)]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);
        await _downloads.RunCycleAsync(CancellationToken.None);
        await _downloads.SearchAsync("movie:12", CancellationToken.None);
        var nudges = 0;
        _downloads.Nudged += () => nudges++;

        Assert.Equal(GrabOutcome.Ok, await _downloads.GrabAsync("movie:12", "a", 1, CancellationToken.None));

        Assert.Equal(1, nudges);
    }
}
