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
    public async Task AStalledPackInWarningIsRemoved()
    {
        WholeSeason();
        _releases = [Pack("pack", 3, 50)];
        await Cycle();
        _releases = [];

        // stalledDL di qBittorrent (ruling 11): un elemento in "warning", gli altri in "downloading".
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(91, 201, 5_000), EpisodeQueue(92, 202, 5_000), EpisodeQueue(93, 203, 5_000)];
        _sonarrQueue[0]!.Status = "warning";
        await Cycle();

        SearchesFail();
        _time.Advance(DownloadSchedule.StalledAfter);
        await Cycle();

        Assert.Equal([91, 92, 93], _arr.RemoveFromQueueCalls.Select(c => c.QueueId));
        Assert.Equal(DownloadStates.Waiting, Saved("season:7:2")!.State);
    }

    // Stagione 2 di sei episodi: 1 e 2 già scaricati, 3-6 mancanti; la ricerca di stagione trova un pack di 3-4 e il singolo 5.
    private void PartlyDownloadedSeason(int packScore = 50)
    {
        _seriesEpisodes = [.. Enumerable.Range(1, 6).Select(n => (SonarrEpisode?)Ep(200 + n, n, T0 - TimeSpan.FromDays(40 - n)))];
        foreach (var episode in _seriesEpisodes.Take(2))
        {
            (episode!.HasFile, episode.EpisodeFileId) = (true, 100 + episode.Id);
        }

        _missing = [.. _seriesEpisodes.Skip(2)];
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>([new SonarrSeries { Id = 7, Title = "Severance", Runtime = 50, QualityProfileId = 6 }]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([SeasonFile(301, 2, 150), SeasonFile(302, 2, 150)]);
        var pack = Release("p34", WebRip1080, "WEBRip-1080p", 3, packScore);
        (pack.EpisodeNumbers, pack.SeasonNumber) = ([3, 4], 2);
        _arr.Releases = (_, query) => Task.FromResult<IReadOnlyList<ArrRelease?>>(query.StartsWith("seriesId", StringComparison.Ordinal) ? [pack, Single("e5", 5, 1, 150)] : []);
    }

    [Fact]
    public async Task AnAdminPackOnAPartlyDownloadedSeasonTakesOnlyItsEpisodes()
    {
        PartlyDownloadedSeason();
        await _service.SearchAsync("season:7:2", CancellationToken.None);
        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("season:7:2", "p34", 1, CancellationToken.None));
        var entry = Saved("season:7:2")!;
        Assert.Equal([3, 4], entry.EpisodeNumbers!);
        Assert.Null(entry.PreviousScore);

        // Il pack in coda è della voce di stagione; 5 e 6 restano episodi e si cercano (ruling 13).
        _sonarrQueue = [EpisodeQueue(91, 203, 5_000), EpisodeQueue(92, 204, 5_000)];
        await Cycle();
        Assert.Equal(["episode:205", "episode:206", "season:7:2"], SavedKeys());
        Assert.Equal((DownloadStates.Downloading, (int?)91), (Saved("season:7:2")!.State, Saved("season:7:2")!.QueueId));
        Assert.Equal(["episodeId=205", "episodeId=206"], _arr.SearchReleaseCalls.Skip(1).Select(c => c.Query).Order(StringComparer.Ordinal));

        // Importato: 3 e 4 hanno il file, 5 e 6 mancano ancora. La voce di stagione è importata, non torna in attesa.
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        _missing = [.. _seriesEpisodes.Skip(4)];
        await Cycle();
        entry = Saved("season:7:2")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)50), (entry.State, entry.CurrentScore));
        Assert.Equal(["episode:205", "episode:206", "season:7:2"], SavedKeys());
    }

    [Fact]
    public async Task AnAdminSingleFromASeasonSearchIsAnEpisode()
    {
        PartlyDownloadedSeason();
        await _service.SearchAsync("season:7:2", CancellationToken.None);

        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("season:7:2", "e5", 1, CancellationToken.None));

        Assert.Null(Saved("season:7:2"));
        var entry = Saved("episode:205")!;
        Assert.Equal((DownloadKinds.Episode, "Severance · S02E05", DownloadStates.Downloading, (int?)null), (entry.Kind, entry.Title, entry.State, entry.PreviousScore));
        Assert.Null(entry.EpisodeNumbers);
        Assert.Equal(("episode:205", "e5"), (Store().Load().Choices[0].Key, Store().Load().Choices[0].Guid));

        // Il giro la segue come episodio.
        _sonarrQueue = [EpisodeQueue(91, 205, 5_000)];
        await Cycle();
        Assert.Equal((DownloadStates.Downloading, (int?)91), (Saved("episode:205")!.State, Saved("episode:205")!.QueueId));
        Assert.Null(Saved("season:7:2"));
    }

    [Fact]
    public async Task AnAdminSingleOnASeasonInUpgradeWatchKeepsItsDownload()
    {
        // La stagione tiene d'occhio gli upgrade con i tre file del pack (50 punti); la sua ricerca trova un singolo di e2 da 150.
        await GrabAndImportPack();
        foreach (var episode in _seriesEpisodes)
        {
            (episode!.HasFile, episode.EpisodeFileId) = (true, 800 + episode.EpisodeNumber);
        }

        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>([new SonarrSeries { Id = 7, Title = "Severance", Runtime = 50, QualityProfileId = 6 }]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([SeasonFile(801, 2, 50), SeasonFile(802, 2, 50), SeasonFile(803, 2, 50)]);
        _releases = [Single("e2", 2, 1, 150)];
        await _service.SearchAsync("season:7:2", CancellationToken.None);
        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("season:7:2", "e2", 1, CancellationToken.None));
        _releases = [];
        Assert.Equal((DownloadStates.Downloading, (int?)50), (Saved("episode:202")!.State, Saved("episode:202")!.PreviousScore));
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("season:7:2")!.State);

        // Il download in coda è dell'episodio, non della stagione.
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [EpisodeQueue(94, 202, 5_000)];
        await Cycle();
        Assert.Equal((DownloadStates.Downloading, (int?)94), (Saved("episode:202")!.State, Saved("episode:202")!.QueueId));
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("season:7:2")!.State);

        // Importato: il file nuovo da 150 conferma l'upgrade (all'obiettivo, la voce esce), niente ritorno al punteggio vecchio.
        _seriesEpisodes[1]!.EpisodeFileId = 902;
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([SeasonFile(801, 2, 50), SeasonFile(902, 2, 150), SeasonFile(803, 2, 50)]);
        _time.Advance(DownloadService.CycleInterval);
        _sonarrQueue = [];
        await Cycle();
        Assert.Null(Saved("episode:202"));
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("season:7:2")!.State);
        Assert.Single(_arr.GrabCalls, c => c.Guid == "e2");
    }

    [Fact]
    public async Task AnAdminSingleInFlightIsNotGrabbedByTheCycle()
    {
        // Il singolo e5 si trova anche con la ricerca dell'episodio.
        PartlyDownloadedSeason();
        var pack = Release("p34", WebRip1080, "WEBRip-1080p", 3, 50);
        (pack.EpisodeNumbers, pack.SeasonNumber) = ([3, 4], 2);
        _arr.Releases = (_, query) => Task.FromResult<IReadOnlyList<ArrRelease?>>(
            query.StartsWith("seriesId", StringComparison.Ordinal) ? [pack, Single("e5", 5, 1, 150)]
            : query == "episodeId=205" ? [Single("e5", 5, 1, 150)]
            : []);
        await _service.SearchAsync("season:7:2", CancellationToken.None);
        var adminGrab = new TaskCompletionSource();
        var grabs = 0;
        _arr.Grab = (_, _, _) => grabs++ == 0 ? adminGrab.Task : Task.CompletedTask;
        var admin = _service.GrabAsync("season:7:2", "e5", 1, CancellationToken.None);

        // Il giro arriva al grab di episode:205 mentre l'admin lo sta scaricando: lo salta (ruling 8).
        await Cycle().WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Single(_arr.GrabCalls);

        adminGrab.SetResult();
        Assert.Equal(GrabOutcome.Ok, await admin);
        Assert.Equal(DownloadStates.Downloading, Saved("episode:205")!.State);
        Assert.True(Store().Load().Choices.Single(c => c.Key == "episode:205").ByAdmin);
    }

    [Fact]
    public async Task AnAdminPackRemovesTheWaitingEpisodesItCovers()
    {
        // 3, 5 e 6 voci in attesa, 4 già in coda; l'admin scarica il pack di 3-4 senza una voce di stagione.
        PartlyDownloadedSeason();
        _sonarrQueue = [EpisodeQueue(80, 204, 5_000)];
        await Cycle();
        Assert.Equal(["episode:203", "episode:204", "episode:205", "episode:206"], SavedKeys());
        Assert.Equal(DownloadStates.Downloading, Saved("episode:204")!.State);

        await _service.SearchAsync("season:7:2", CancellationToken.None);
        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("season:7:2", "p34", 1, CancellationToken.None));

        // Subito, non al giro dopo: un giro in corso non scarica più l'episodio 3; il 4 che scarica resta.
        Assert.Equal(["episode:204", "episode:205", "episode:206", "season:7:2"], SavedKeys());
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
