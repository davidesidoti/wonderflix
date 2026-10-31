using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Gli avvisi agli admin dello spazio (spec V): operazione fallita, disco quasi pieno e Alleggerisci bloccati.</summary>
public sealed class SpaceAlertsTests : IDisposable
{
    private const long Gb = 1_000_000_000;
    private const string QuotaPath = "/home/user/quota.txt";

    private readonly TempFolder _folder = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero));
    private readonly FakeServer _server = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeFileProbe _probe = new();
    private readonly FakeSpaceSettings _settings = new() { QuotaFile = QuotaPath };
    private readonly InboxService _inbox;
    private readonly SpaceService _space;
    private readonly SpaceHostedService _hosted;
    private readonly Guid _admin;
    private List<ArrQueueItem?> _radarrQueue = [];

    public SpaceAlertsTests()
    {
        _admin = _server.AddUser("Anna", isAdmin: true).Id;
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : []);
        _inbox = TestInbox.Create(_server, _folder, _time);
        var alerts = new AdminAlerts(_inbox, _server, _time, NullLogger<AdminAlerts>.Instance);
        _space = new SpaceService(
            _arr,
            new FakeSeerrClient(),
            new FakeSeerrSettings(),
            new FakeQbitClient(),
            _probe,
            new FakeLibraryRefresh(),
            _settings,
            new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance),
            new FakeViewingFacts(),
            new FakeSeriesIndex(),
            TestRatings.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time)),
            _server,
            TestDownloads.Create(_arr, _time, _folder.DownloadsFile),
            _time,
            NullLogger<SpaceService>.Instance,
            alerts);
        _hosted = new SpaceHostedService(_space, alerts, _time, NullLogger<SpaceHostedService>.Instance);
    }

    public void Dispose()
    {
        _hosted.Dispose();
        _folder.Dispose();
    }

    private IReadOnlyList<InboxEntry> Entries() => _inbox.Get(_admin).Entries;

    // La riga di quota -w: blocchi da 1 KB usati, quota e limite.
    private void Quota(long used, long limit) => _probe.Texts[QuotaPath] = $"/dev/sda1 {used} {limit} {limit} 0 0 0";

    private static SpaceScan Scan(params string[] keys) => new()
    {
        Lighten = [.. keys.Select(k => new ScanRow<SpaceLightenDto>(
            new SpaceLightenDto(k, SpaceKinds.Movie, "Titolo " + k, null, null, null, 12 * Gb, 6 * Gb, 6.5, null), [k], []))],
    };

    private void Lightened(params string[] keys)
    {
        var store = new DownloadStore(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);
        var book = store.Load();
        foreach (var key in keys)
        {
            book.MarkLightened(key, _time.GetUtcNow().AddHours(-1));
        }

        store.Save(book);
    }

    private static ArrQueueItem Item(int movieId, string state) =>
        new() { MovieId = movieId, Size = 4 * Gb, Sizeleft = 0, TrackedDownloadState = state, DownloadId = "D" + movieId };

    private static async Task<bool> Eventually(Func<bool> condition)
    {
        for (var i = 0; i < 100 && !condition(); i++)
        {
            await Task.Delay(50);
        }

        return condition();
    }

    [Fact]
    public void QuotaAlert_AtThreshold_Returned()
    {
        Quota(900, 1000);

        Assert.Equal(new AdminAlert("quota", InboxEntryTypes.DiskAlmostFull, "Spazio", Percent: 90), _space.QuotaAlert());
    }

    [Fact]
    public void QuotaAlert_Below_Null()
    {
        Quota(899, 1000);

        Assert.Null(_space.QuotaAlert());
    }

    [Fact]
    public void QuotaAlert_NoQuotaFile_Null()
    {
        Assert.Null(_space.QuotaAlert());
        _settings.QuotaFile = "";
        Assert.Null(_space.QuotaAlert());
    }

    [Fact]
    public async Task Abort_RaisesSpaceOperationFailed()
    {
        // Un'operazione rimasta in corso a un riavvio risulta fallita alla lettura del file.
        var store = new SpaceStore(_folder.SpaceFile, NullLogger<SpaceStore>.Instance);
        var book = store.Load();
        book.AddOperation(new SpaceOperation
        {
            Id = "op1",
            Kind = SpaceKinds.Movie,
            Key = "movie:12",
            Title = "Coco",
            State = SpaceOperationStates.Running,
            StartedAt = _time.GetUtcNow(),
        });
        store.Save(book);

        _space.Load();

        Assert.True(await Eventually(() => Entries().Count > 0));
        var entry = Assert.Single(Entries());
        Assert.Equal(("space-op:op1", InboxEntryTypes.SpaceOperationFailed, "Coco"), (entry.AlertKey, entry.Type, entry.Title));

        // Il fallimento è salvato: un altro riavvio non lo notifica di nuovo.
        Assert.Equal(SpaceOperationStates.Failed, store.Load().Operation("op1")!.State);
    }

    [Fact]
    public async Task LightenAlerts_BlockedOnly()
    {
        Assert.Empty(await _space.LightenAlertsAsync(CancellationToken.None));

        Lightened("movie:12", "movie:13");
        _radarrQueue = [Item(12, "importBlocked"), Item(13, "downloading")];
        _space.LastScan = Scan("movie:12", "movie:13", "movie:14");

        var alert = Assert.Single(await _space.LightenAlertsAsync(CancellationToken.None));

        Assert.Equal(new AdminAlert("lighten:movie:12", InboxEntryTypes.LightenBlocked, "Titolo movie:12"), alert);
    }

    [Fact]
    public async Task HostedService_PendingTimer_SyncsQuotaAndLighten()
    {
        // downloads.json si legge una volta sola, al primo uso.
        Lightened("movie:12");
        Quota(950, 1000);
        await _hosted.StartAsync(CancellationToken.None);

        // Dopo il calcolo: la quota (le righe del calcolo finto non hanno download).
        await Task.Run(() => _time.Advance(SpaceHostedService.FirstScanDelay));
        Assert.True(await Eventually(() => Entries().Any(e => e.AlertKey == "quota")));
        Assert.Equal(95, Assert.Single(Entries()).Percent);

        // Al controllo dei torrent in attesa: un Alleggerisci bloccato, e il disco torna sotto la soglia.
        _radarrQueue = [Item(12, "importBlocked")];
        _space.LastScan = Scan("movie:12");
        Quota(800, 1000);
        await Task.Run(() => _time.Advance(SpaceService.PendingInterval - SpaceHostedService.FirstScanDelay));

        Assert.True(await Eventually(() => Entries().Any(e => e.AlertKey == "lighten:movie:12")));
        Assert.True(await Eventually(() => !Entries().Any(e => e.AlertKey == "quota")));
        Assert.Equal(InboxEntryTypes.LightenBlocked, Assert.Single(Entries()).Type);
    }
}
