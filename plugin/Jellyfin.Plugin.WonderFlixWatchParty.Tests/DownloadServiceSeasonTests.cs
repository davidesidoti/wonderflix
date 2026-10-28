using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadServiceSeasonTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    private List<SonarrEpisode?> _missing = [];
    private List<SonarrEpisode?> _seriesEpisodes = [];
    private List<ArrQueueItem?> _sonarrQueue = [];
    private List<ArrRelease?> _releases = [];

    public DownloadServiceSeasonTests()
    {
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_missing);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(_seriesEpisodes);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Sonarr ? _sonarrQueue : []);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);
        _service = NewService();
    }

    public void Dispose() => _folder.Dispose();

    private DownloadService NewService()
    {
        var service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
        service.Load();
        return service;
    }

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    private List<string> SavedKeys() => [.. Store().Load().Entries.Select(e => e.Key).Order(StringComparer.Ordinal)];

    private Task<CycleReport> Cycle() => _service.RunCycleAsync(CancellationToken.None);

    // Episodio n della stagione 2 di Severance (serie 7).
    private static SonarrEpisode Ep(int id, int number, DateTimeOffset? airDate)
    {
        var episode = Episode(id, airDate);
        episode.EpisodeNumber = number;
        return episode;
    }

    // La stagione 2 finita da due settimane, tre episodi tutti mancanti.
    private void WholeSeason()
    {
        _seriesEpisodes = [Ep(201, 1, T0 - TimeSpan.FromDays(30)), Ep(202, 2, T0 - TimeSpan.FromDays(23)), Ep(203, 3, T0 - TimeSpan.FromDays(16))];
        _missing = [.. _seriesEpisodes];
    }

    // La ricerca non risponde: la voce resta com'è, così il test la guarda prima della scelta.
    private void SearchesFail() =>
        _arr.Releases = (_, _) => Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unreachable));

    private static ArrRelease Pack(string guid, double gb, int score)
    {
        var release = Release(guid, WebRip1080, "WEBRip-1080p", gb, score);
        release.FullSeason = true;
        release.SeasonNumber = 2;
        return release;
    }

    private static ArrRelease Single(string guid, int episode, double gb, int score)
    {
        var release = Release(guid, WebRip1080, "WEBRip-1080p", gb, score);
        release.EpisodeNumbers = [episode];
        release.SeasonNumber = 2;
        return release;
    }

    private static ArrFile SeasonFile(int id, int season, int score)
    {
        var file = File(id, WebRip1080, score);
        file.SeasonNumber = season;
        return file;
    }

    // Il pack leggero scaricato, visto in coda (un elemento per episodio) e importato: la stagione tiene d'occhio gli upgrade.
    private async Task GrabAndImportPack()
    {
        WholeSeason();
        _releases = [Pack("pack", 3, 50)];
        await Cycle();
        _releases = [];

        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(91, 201, 5_000), EpisodeQueue(92, 202, 5_000), EpisodeQueue(93, 203, 5_000)];
        await Cycle();

        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        _missing = [];
        await Cycle();
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("season:7:2")!.State);
    }

    [Fact]
    public async Task AFinishedMissingSeasonIsOneEntry()
    {
        WholeSeason();
        SearchesFail();

        await Cycle();

        Assert.Equal([7], _arr.SeriesEpisodeCalls);
        Assert.Equal((ArrKind.Sonarr, "seriesId=7&seasonNumber=2"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.Equal(["season:7:2"], SavedKeys());
        var entry = Saved("season:7:2")!;
        Assert.Equal((DownloadKinds.Season, "Severance · Stagione 2", "https://img.example/sev.jpg"), (entry.Kind, entry.Title, entry.PosterUrl));
        Assert.Equal((DownloadStates.Waiting, T0 - TimeSpan.FromDays(16)), (entry.State, entry.AvailableSince));
        Assert.Equal((6, 50, 7), (entry.ProfileId, entry.RuntimeMinutes, entry.SeriesId));
    }

    [Fact]
    public async Task ASeasonStillAiringStaysEpisodes()
    {
        var finale = T0 + TimeSpan.FromDays(7);
        _seriesEpisodes = [Ep(201, 1, T0 - TimeSpan.FromDays(14)), Ep(202, 2, T0 - TimeSpan.FromDays(7)), Ep(203, 3, finale)];
        _missing = [_seriesEpisodes[0], _seriesEpisodes[1]];
        SearchesFail();

        await Cycle();
        Assert.Equal(["episode:201", "episode:202"], SavedKeys());

        // Un episodio senza data: la stagione non è ancora finita.
        _seriesEpisodes[2] = Ep(203, 3, null);
        _time.Advance(DownloadService.CycleInterval);
        await Cycle();
        Assert.Equal(["episode:201", "episode:202"], SavedKeys());

        // Va in onda l'ultimo: una voce sola al posto degli episodi.
        _time.Advance(TimeSpan.FromDays(8));
        _seriesEpisodes[2] = Ep(203, 3, finale);
        _missing = [.. _seriesEpisodes];
        await Cycle();
        Assert.Equal(["season:7:2"], SavedKeys());
        Assert.Equal(finale, Saved("season:7:2")!.AvailableSince);
        Assert.Equal((ArrKind.Sonarr, "seriesId=7&seasonNumber=2"), _arr.SearchReleaseCalls[^1]);
    }

    [Fact]
    public async Task APartlyDownloadedSeasonStaysEpisodes()
    {
        WholeSeason();
        _missing = [_seriesEpisodes[0], _seriesEpisodes[1]];

        await Cycle();

        Assert.Equal(["episode:201", "episode:202"], SavedKeys());
        Assert.DoesNotContain(_arr.SearchReleaseCalls, c => c.Query.StartsWith("seriesId", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ASeasonWithAnEpisodeInTheQueueStaysEpisodes()
    {
        WholeSeason();
        _sonarrQueue = [EpisodeQueue(91, 201, 5_000)];

        await Cycle();

        Assert.Equal(["episode:201", "episode:202", "episode:203"], SavedKeys());
        Assert.Equal(DownloadStates.Downloading, Saved("episode:201")!.State);
    }

    [Fact]
    public async Task ASeriesReadErrorKeepsEpisodes()
    {
        WholeSeason();
        _arr.SeriesEpisodes = _ => Task.FromException<IReadOnlyList<SonarrEpisode?>>(new ArrException(ArrError.Unreachable));

        var report = await Cycle();

        Assert.Null(report.SonarrError);
        Assert.Equal(["episode:201", "episode:202", "episode:203"], SavedKeys());
    }

    [Fact]
    public async Task ALightPackIsGrabbed()
    {
        WholeSeason();
        _releases = [Pack("pack", 3, 50), Single("e1", 1, 1, 50), Single("e2", 2, 1, 50), Single("e3", 3, 1, 50)];

        var report = await Cycle();

        Assert.Equal((1, 1), (report.Searched, report.Grabbed));
        Assert.Equal((ArrKind.Sonarr, "pack", 1), Assert.Single(_arr.GrabCalls));
        var entry = Saved("season:7:2")!;
        Assert.Equal((DownloadStates.Downloading, (int?)50), (entry.State, entry.CurrentScore));
        var choice = Assert.Single(Store().Load().Choices);
        Assert.Equal(("season:7:2", DownloadKinds.Season, "Severance · Stagione 2"), (choice.Key, choice.Kind, choice.Title));

        // Sonarr mette in coda un elemento per episodio: è la voce di stagione che scarica.
        _releases = [];
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(93, 203, 5_000), EpisodeQueue(91, 201, 5_000), EpisodeQueue(92, 202, 5_000)];
        await Cycle();
        Assert.Equal(["season:7:2"], SavedKeys());
        Assert.Equal((DownloadStates.Downloading, (int?)91), (Saved("season:7:2")!.State, Saved("season:7:2")!.QueueId));

        // Importato: niente in coda e niente più tra i mancanti. Sotto l'obiettivo si tengono d'occhio gli upgrade.
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        _missing = [];
        await Cycle();
        entry = Saved("season:7:2")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)50), (entry.State, entry.CurrentScore));
        Assert.Equal(T0 + DownloadSchedule.UpgradeWindow, entry.UpgradeUntil);
        Assert.Single(_arr.GrabCalls);
    }

    [Fact]
    public async Task AHeavyPackSplitsIntoEpisodes()
    {
        WholeSeason();
        _releases = [Pack("pack", 5, 50), Single("e1", 1, 1, 50), Single("e2", 2, 1, 50), Single("e3", 3, 1, 50)];

        await Cycle();

        // Niente download e niente ricerche in più: gli episodi si cercano dal giro dopo.
        Assert.Empty(_arr.GrabCalls);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Equal(["episode:201", "episode:202", "episode:203"], SavedKeys());
        var first = Saved("episode:201")!;
        Assert.Equal((DownloadStates.Waiting, (DateTimeOffset?)T0, T0 - TimeSpan.FromDays(30)), (first.State, first.NextSearchAt, first.AvailableSince));

        // Il giro dopo, anche dopo un riavvio, restano episodi.
        _releases = [];
        _time.Advance(DownloadService.CycleInterval);
        await NewService().RunCycleAsync(CancellationToken.None);
        Assert.Equal(["episode:201", "episode:202", "episode:203"], SavedKeys());
        Assert.Equal(
            ["episodeId=201", "episodeId=202", "episodeId=203"],
            _arr.SearchReleaseCalls.Skip(1).Select(c => c.Query).Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task AStalledPackIsRemovedOnce()
    {
        WholeSeason();
        _releases = [Pack("pack", 3, 50)];
        await Cycle();
        _releases = [];

        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(91, 201, 5_000), EpisodeQueue(92, 202, 5_000), EpisodeQueue(93, 203, 5_000)];
        await Cycle();

        // Togliere il primo toglie il pack: gli altri elementi non ci sono più.
        _arr.RemoveFromQueue = (_, id, _) => id == 91 ? Task.CompletedTask : Task.FromException(new ArrException(ArrError.Unreachable));
        SearchesFail();
        _time.Advance(DownloadSchedule.StalledAfter);
        await Cycle();

        Assert.Equal([91, 92, 93], _arr.RemoveFromQueueCalls.Select(c => c.QueueId));
        var entry = Saved("season:7:2")!;
        Assert.Equal((DownloadStates.Waiting, (int?)null, (int?)null), (entry.State, entry.QueueId, entry.CurrentScore));
    }

    [Fact]
    public async Task AFailedPackStaysASeason()
    {
        WholeSeason();
        _releases = [Pack("pack", 3, 50)];
        await Cycle();
        _releases = [];

        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(91, 201, 5_000), EpisodeQueue(92, 202, 5_000), EpisodeQueue(93, 203, 5_000)];
        await Cycle();

        // Fuori dalla coda ma gli episodi mancano ancora: fallito.
        SearchesFail();
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        await Cycle();

        Assert.Equal(["season:7:2"], SavedKeys());
        Assert.Equal(DownloadStates.Waiting, Saved("season:7:2")!.State);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ASeasonUpgradeIsConfirmedByTheFiles(bool stillTheOldFiles)
    {
        await GrabAndImportPack();

        _time.Advance(TimeSpan.FromHours(6));
        _releases = [Pack("pack-ita-eng", 3, 150)];
        await Cycle();
        _releases = [];
        Assert.Equal((ArrKind.Sonarr, "pack-ita-eng", 1), _arr.GrabCalls[^1]);

        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(94, 201, 5_000), EpisodeQueue(95, 202, 5_000), EpisodeQueue(96, 203, 5_000)];
        await Cycle();

        var score = stillTheOldFiles ? 50 : 150;
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
            [SeasonFile(801, 2, score), SeasonFile(802, 2, score), SeasonFile(803, 2, score), SeasonFile(700, 1, 150)]);
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        await Cycle();

        Assert.Equal([7], _arr.EpisodeFileCalls);
        if (stillTheOldFiles)
        {
            var entry = Saved("season:7:2")!;
            Assert.Equal((DownloadStates.UpgradeWatch, (int?)50, (int?)null), (entry.State, entry.CurrentScore, entry.PreviousScore));
        }
        else
        {
            // All'obiettivo: la voce esce.
            Assert.Null(Saved("season:7:2"));
        }
    }
}
