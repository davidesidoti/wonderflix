using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadsHostedServiceTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);
    private static readonly TimeSpan Second = TimeSpan.FromSeconds(1);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly RecordingLogger<DownloadsHostedService> _logger = new();
    private readonly DownloadService _downloads;
    private readonly DownloadsHostedService _hosted;
    private TaskCompletionSource<IReadOnlyList<SonarrEpisode?>>? _gate;
    private int _cycles;

    public DownloadsHostedServiceTests()
    {
        // Un giro si riconosce dalla lettura degli episodi mancanti (l'elenco da ripassare non la fa); il cancello lo tiene aperto.
        _arr.MissingEpisodes = () =>
        {
            Interlocked.Increment(ref _cycles);
            return _gate?.Task ?? Task.FromResult<IReadOnlyList<SonarrEpisode?>>([]);
        };
        _downloads = TestDownloads.Create(_arr, _time, _folder.DownloadsFile);
        _hosted = new DownloadsHostedService(_downloads, _time, _logger);
    }

    public void Dispose()
    {
        _gate?.TrySetResult([]);
        _hosted.Dispose();
        _folder.Dispose();
    }

    private void Hold() => _gate = new(TaskCreationOptions.RunContinuationsAsynchronously);

    // Fa passare il tempo a piccoli passi finché la condizione non si avvera: il giro finisce su un altro thread.
    private bool AdvanceUntil(Func<bool> done, TimeSpan? step = null)
    {
        for (var i = 0; i < 200; i++)
        {
            if (done())
            {
                return true;
            }

            _time.Advance(step ?? Second);
            Thread.Sleep(5);
        }

        return done();
    }

    [Fact]
    public async Task OneCycleAtATime()
    {
        await _hosted.StartAsync(CancellationToken.None);
        Hold();

        _time.Advance(DownloadService.CycleInterval);
        Assert.Equal(1, Volatile.Read(ref _cycles));

        // Il giro è ancora in corso: i tick dopo saltano.
        _time.Advance(DownloadService.CycleInterval);
        _time.Advance(DownloadService.CycleInterval);
        Assert.Equal(1, Volatile.Read(ref _cycles));

        // Finito, il tick dopo ne fa partire uno nuovo.
        _gate!.SetResult([]);
        _gate = null;
        Assert.True(AdvanceUntil(() => Volatile.Read(ref _cycles) == 2, DownloadService.CycleInterval));
    }

    [Fact]
    public async Task ANudgeRunsACycleAfterAMinute()
    {
        await _hosted.StartAsync(CancellationToken.None);

        // Due nudge vicini fanno un giro solo, un minuto dopo il primo.
        _downloads.Nudge();
        _downloads.Nudge();
        _time.Advance(DownloadService.NudgeDelay - Second);
        Assert.Equal(0, Volatile.Read(ref _cycles));
        _time.Advance(Second);
        Assert.Equal(1, Volatile.Read(ref _cycles));
        _time.Advance(DownloadService.NudgeDelay);
        Assert.Equal(1, Volatile.Read(ref _cycles));
    }

    [Fact]
    public async Task ANudgeDuringACycleRunsOneMoreCycleAfterIt()
    {
        await _hosted.StartAsync(CancellationToken.None);
        Hold();
        _downloads.Nudge();
        _time.Advance(DownloadService.NudgeDelay);
        Assert.Equal(1, Volatile.Read(ref _cycles));

        // Un altro nudge a giro in corso: nessun giro in parallelo, ma uno dopo.
        _downloads.Nudge();
        _time.Advance(DownloadService.NudgeDelay);
        Assert.Equal(1, Volatile.Read(ref _cycles));

        _gate!.SetResult([]);
        _gate = null;
        Assert.True(AdvanceUntil(() => Volatile.Read(ref _cycles) == 2));
        _time.Advance(DownloadService.NudgeDelay * 2);
        Assert.Equal(2, Volatile.Read(ref _cycles));
    }

    [Fact]
    public async Task AFailingCycleIsLogged()
    {
        // Il file non si può scrivere (la cartella è un file): il giro lancia, il timer no.
        var blocker = Path.Combine(_folder.Path, "blocker");
        Directory.CreateDirectory(_folder.Path);
        await File.WriteAllTextAsync(blocker, "x");
        using var hosted = new DownloadsHostedService(
            TestDownloads.Create(_arr, _time, Path.Combine(blocker, "downloads.json")), _time, _logger);
        await hosted.StartAsync(CancellationToken.None);

        _time.Advance(DownloadService.CycleInterval);

        Assert.True(AdvanceUntil(() => _logger.Entries.Any(e => e.Level == LogLevel.Warning && e.Exception is not null)));
        var calls = Volatile.Read(ref _cycles);
        _time.Advance(DownloadService.CycleInterval);
        Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref _cycles) > calls, 2000));
    }

    [Fact]
    public async Task TheReviewRunsAfterFiveMinutesAndStopCancelsTheTimers()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        await _hosted.StartAsync(CancellationToken.None);

        _time.Advance(DownloadsHostedService.FirstReviewDelay - Second);
        Assert.Equal(0, _arr.LibraryMovieCalls);
        _time.Advance(Second);
        Assert.True(SpinWait.SpinUntil(() => _arr.LibraryMovieCalls > 0, 2000));

        await _hosted.StopAsync(CancellationToken.None);
        var calls = _arr.LibraryMovieCalls;
        _time.Advance(DownloadService.ReviewInterval);
        Assert.Equal(calls, _arr.LibraryMovieCalls);
    }
}
