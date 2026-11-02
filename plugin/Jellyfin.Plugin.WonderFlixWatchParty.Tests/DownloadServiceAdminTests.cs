using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadServiceAdminTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    private List<RadarrMovie?> _movies = [];
    private List<ArrQueueItem?> _radarrQueue = [];
    private List<ArrQueueItem?> _sonarrQueue = [];
    private List<ArrRelease?> _releases = [];
    private List<ArrFile?> _movieFiles = [];

    public DownloadServiceAdminTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : _sonarrQueue);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(_movieFiles);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }, new ArrIndexer { Id = 3, Priority = 10 }]);

        // Niente Load(): un test può scrivere downloads.json prima che il servizio lo legga.
        _service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
    }

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    private Task<DownloadSearchDto?> Search(string key) => _service.SearchAsync(key, CancellationToken.None);

    private Task<GrabOutcome> Grab(string key, string guid, int indexerId) => _service.GrabAsync(key, guid, indexerId, CancellationToken.None);

    // Animals (106 minuti): tre WEB 1080p da 150 e uno troppo leggero (1,1 GB = 0,62 GB/ora).
    private void Animals()
    {
        _movies = [Movie(12, title: "Animals", year: 2025, runtime: 106)];
        _releases =
        [
            Release("a", WebDl1080, "WEBDL-1080p", 2.9, 150),
            Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3),
            Release("c", WebRip1080, "WEBRip-1080p", 4.83, 150),
            Release("d", WebRip1080, "WEBRip-1080p", 1.1, 150),
        ];
    }

    // Animals con un Bluray-1080p da 0 punti e 12,4 GB già in Radarr (file 512).
    private void AnimalsOnBluray()
    {
        Animals();
        _movies = [Movie(12, hasFile: true, title: "Animals", year: 2025, runtime: 106)];
        var file = File(512, Bluray1080, 0);
        file.Size = (long)(12.4 * Gb);
        file.Quality!.Quality!.Name = "Bluray-1080p";
        _movieFiles = [file];
    }

    private void ReviewOf(params string[] keys)
    {
        var book = new DownloadBook();
        book.SetReview([.. keys.Select(k => new ReviewItem { Key = k, Kind = DownloadKinds.Movie, Title = k, Score = 0, SizeBytes = Gb, Quality = "Bluray-1080p" })], T0);
        Store().Save(book);
    }

    [Fact]
    public async Task SearchMarksTheChoiceAndRejected()
    {
        Animals();

        // Una release senza guid non si può scaricare: la regola non la guarda e non si conta.
        _releases = [.. _releases, Release("", WebRip1080, "WEBRip-1080p", 2, 150)];

        var result = (await Search("movie:12"))!;

        Assert.Equal(("movie:12", DownloadKinds.Movie, "Animals (2025)", 106, (string?)null), (result.Key, result.Kind, result.Title, result.RuntimeMinutes, result.Error));
        Assert.Null(result.Current);
        Assert.Equal((ArrKind.Radarr, "movieId=12"), Assert.Single(_arr.SearchReleaseCalls));

        // Il limite lungo dell'admin, non quello del giro.
        Assert.Null(_arr.LastReleaseTimeout);

        // Solo il film, non tutta la libreria di Radarr (ruling 14).
        Assert.Equal([12], _arr.MovieByIdCalls);
        Assert.Equal(0, _arr.LibraryMovieCalls);
        Assert.Equal(["b", "a", "c"], result.Candidates.Select(c => c.Release.Guid));
        Assert.Equal([1, 2, 3], result.Candidates.Select(c => c.Rank));
        Assert.Equal([true, false, false], result.Candidates.Select(c => c.IsChoice));
        Assert.All(result.Candidates, c => Assert.True(c.WouldImport));
        Assert.Equal(("b", 3, "idx3", "t-b", "WEBRip-1080p", 1080, (long)(1.89 * Gb), 150, (int?)10), Flat(result.Candidates[0].Release));

        var rejected = Assert.Single(result.Rejected);
        Assert.Equal(("d", "TooSmall", (string?)"0.62"), (rejected.Release.Guid, rejected.Reason, rejected.Detail));
        Assert.Equal((3, 4), (result.ValidCount, result.TotalCount));

        // Una ricerca non crea voci: il titolo può venire da "Da ripassare".
        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task SearchShowsTheCurrentFile()
    {
        AnimalsOnBluray();
        _releases = [.. _releases, Release("e", Bluray1080, "Bluray-1080p", 9, 10)];

        var result = (await Search("movie:12"))!;

        Assert.Equal([512], Assert.Single(_arr.MovieFileCalls));
        Assert.Equal(((long)(12.4 * Gb), 0, "Bluray-1080p"), (result.Current!.SizeBytes, result.Current.Score, result.Current.Quality));

        // Un WEB 1080p sta sotto il Bluray nel profilo: Radarr lo importa solo il Bluray con più punti.
        Assert.Equal(["b", "a", "c", "e"], result.Candidates.Select(c => c.Release.Guid));
        Assert.Equal([false, false, false, true], result.Candidates.Select(c => c.WouldImport));
    }

    [Fact]
    public async Task AnInvalidKeyIsNull()
    {
        Animals();

        Assert.Null(await Search("film:12"));
        Assert.Null(await Search("movie:0"));
        Assert.Null(await Search("movie:99"));
        Assert.Empty(_arr.SearchReleaseCalls);

        Assert.Equal(GrabOutcome.Invalid, await Grab("film:12", "b", 3));
        Assert.Equal(GrabOutcome.Invalid, await Grab("movie:12", "", 3));
        Assert.Equal(GrabOutcome.Invalid, await Grab("movie:99", "b", 3));
        Assert.False(_service.Accept("film:12"));
        Assert.False(_service.SearchNow("movie:12"));
        Assert.Empty(_arr.GrabCalls);
    }

    [Fact]
    public async Task GrabUsesTheLastSearch()
    {
        ReviewOf("movie:12", "movie:13");
        Animals();
        await Search("movie:12");

        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "b", 3));

        Assert.Equal((ArrKind.Radarr, "b", 3), Assert.Single(_arr.GrabCalls));
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Empty(_arr.RemoveFromQueueCalls);

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, DownloadKinds.Movie, "Animals (2025)", 4, 106), (entry.State, entry.Kind, entry.Title, entry.ProfileId, entry.RuntimeMinutes));
        Assert.Equal(((int?)150, (int?)WebRip1080, (int?)null, "Main", false), (entry.CurrentScore, entry.CurrentQualityId, entry.PreviousScore, entry.ProfileName, entry.ManualImportPending));

        var choice = Assert.Single(Store().Load().Choices);
        Assert.Equal(("b", true, (int?)null, (long?)null), (choice.Guid, choice.ByAdmin, choice.PreviousScore, choice.PreviousSizeBytes));

        // Esce da "Da ripassare" senza diventare "va bene così"; la panoramica la mostra.
        var overview = await _service.OverviewAsync(CancellationToken.None);
        Assert.Equal(["movie:13"], overview.Review.Select(r => r.Key));
        Assert.Empty(Store().Load().ToFile().Accepted);
        var recent = Assert.Single(overview.Recent);
        Assert.Equal(("movie:12", "Animals (2025)", "b", true), (recent.Key, recent.Title, recent.Release.Guid, recent.ByAdmin));
        var waiting = Assert.Single(overview.Waiting);
        Assert.Equal(("movie:12", DownloadStates.Downloading, T0), (waiting.Key, waiting.State, waiting.AvailableSince));
        Assert.True(overview.Enabled);
    }

    [Fact]
    public async Task ALightenGrabIsAccepted()
    {
        Animals();

        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("movie:12", "b", 3, CancellationToken.None, lighten: true));

        Assert.True(Store().Load().IsAccepted("movie:12"));
    }

    [Fact]
    public async Task ALightenGrabIsRemembered()
    {
        Animals();

        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("movie:12", "b", 3, CancellationToken.None, lighten: true));

        Assert.Equal(T0, Store().Load().Lightened["movie:12"]);
        Assert.Equal(T0, _service.LightenedKeys()["movie:12"]);

        _service.ForgetLightened("movie:12");
        Assert.Empty(_service.LightenedKeys());
        Assert.Empty(Store().Load().Lightened);
    }

    [Fact]
    public async Task ALightenGrabStaysOkWhenTheDiskDoesNotWrite()
    {
        Animals();
        Directory.CreateDirectory(_folder.DownloadsFile + ".tmp");

        Assert.Equal(GrabOutcome.Ok, await _service.GrabAsync("movie:12", "b", 3, CancellationToken.None, lighten: true));
    }

    [Fact]
    public async Task AnOrdinaryGrabIsNotAccepted()
    {
        Animals();

        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "b", 3));

        Assert.False(Store().Load().IsAccepted("movie:12"));
        Assert.Empty(Store().Load().Lightened);
    }

    [Fact]
    public async Task AnExpiredReleaseIsSearchedAgain()
    {
        Animals();

        // Mai cercata: si cerca prima di scaricare.
        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "b", 3));
        Assert.Single(_arr.SearchReleaseCalls);

        // Radarr ha dimenticato i risultati (404): si cerca di nuovo e si riprova con la stessa release.
        _time.Advance(TimeSpan.FromMinutes(1));
        var grabs = 0;
        _arr.Grab = (_, _, _) => grabs++ == 0 ? Task.FromException(new ArrException(ArrError.Unreachable, status: 404)) : Task.CompletedTask;
        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "a", 1));
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
        Assert.Equal([("b", 3), ("a", 1), ("a", 1)], _arr.GrabCalls.Select(c => (c.Guid, c.IndexerId)));

        // La release non c'è più nella nuova ricerca: Expired, senza un altro tentativo.
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 400));
        _releases = [.. _releases.Where(r => r!.Guid != "c")];
        Assert.Equal(GrabOutcome.Expired, await Grab("movie:12", "c", 1));
        Assert.Equal(3, _arr.SearchReleaseCalls.Count);
        Assert.Equal(4, _arr.GrabCalls.Count);
        Assert.Equal("a", Store().Load().Choices[0].Guid);
    }

    [Fact]
    public async Task AServiceErrorIsReported()
    {
        Animals();
        _arr.Releases = (_, _) => Task.FromException<IReadOnlyList<ArrRelease?>>(new ArrException(ArrError.Unauthorized, status: 401));

        var result = (await Search("movie:12"))!;
        Assert.Equal(("movie:12", DownloadKinds.Movie, "Unauthorized"), (result.Key, result.Kind, result.Error));
        Assert.Empty(result.Candidates);
        Assert.Empty(result.Rejected);
        Assert.Equal(GrabOutcome.Unavailable, await Grab("movie:12", "b", 3));

        // Radarr/Sonarr rispondono 500 (il client di download rifiuta il torrent): Refused, né Expired né una voce nuova.
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));
        Assert.Equal(GrabOutcome.Refused, await Grab("movie:12", "b", 3));
        Assert.Single(_arr.GrabCalls);
        Assert.Null(Saved("movie:12"));

        // Rete o timeout (nessuno stato): il servizio non risponde.
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable));
        Assert.Equal(GrabOutcome.Unavailable, await Grab("movie:12", "b", 3));
        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task ChangingADownloadRemovesTheOldOne()
    {
        // WonderFlix ha scaricato b, ora in coda come 77.
        Animals();
        await _service.RunCycleAsync(CancellationToken.None);
        _time.Advance(DownloadService.CycleInterval);
        _radarrQueue = [MovieQueue(77, 12, 5_000)];
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal((DownloadStates.Downloading, (int?)77), (Saved("movie:12")!.State, Saved("movie:12")!.QueueId));

        var calls = new List<string>();
        _arr.RemoveFromQueue = (_, id, _) =>
        {
            calls.Add("remove " + id);
            return Task.CompletedTask;
        };
        _arr.Grab = (_, guid, _) =>
        {
            calls.Add("grab " + guid);
            return Task.CompletedTask;
        };
        await Search("movie:12");
        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "a", 1));

        Assert.Equal(["remove 77", "grab a"], calls);
        Assert.Equal((ArrKind.Radarr, 77, false, true), Assert.Single(_arr.RemoveFromQueueCalls));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (int?)null, (int?)150, (int?)WebDl1080), (entry.State, entry.QueueId, entry.CurrentScore, entry.CurrentQualityId));
        Assert.Equal([("a", true), ("b", false)], Store().Load().Choices.Select(c => (c.Guid, c.ByAdmin)));

        // Radarr non ha ancora messo in coda la nuova: un giro subito dopo non scarica di nuovo.
        _radarrQueue = [];
        _time.Advance(DownloadService.NudgeDelay);
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
        Assert.Equal(2, _arr.GrabCalls.Count);
    }

    [Fact]
    public async Task AChangeRightAfterAGrabRemovesItToo()
    {
        // L'admin ha appena scaricato b: la voce non ha ancora il QueueId, ma Radarr l'ha già in coda (78).
        Animals();
        await Search("movie:12");
        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "b", 3));
        Assert.Null(Saved("movie:12")!.QueueId);
        _radarrQueue = [MovieQueue(78, 12, 5_000), MovieQueue(90, 13, 5_000)];

        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "a", 1));

        Assert.Equal((ArrKind.Radarr, 78, false, true), Assert.Single(_arr.RemoveFromQueueCalls));
        Assert.Equal(["b", "a"], _arr.GrabCalls.Select(c => c.Guid));
    }

    [Fact]
    public async Task AChangeRemovesABlockedDownload()
    {
        // Animals fermo in "Serve te" (77, Radarr non lo importa); intanto è stato importato a mano e Radarr risponde 404.
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "movie:12", Kind = DownloadKinds.Movie, Title = "Animals (2025)", State = DownloadStates.NeedsYou, Reason = DownloadReasons.ImportBlocked, QueueId = 77, AvailableSince = T0 });
        Store().Save(book);
        Animals();
        _radarrQueue = [MovieQueue(77, 12, 0, state: "importBlocked", status: "completed")];
        _arr.RemoveFromQueue = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 404));
        await Search("movie:12");

        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "a", 1));

        Assert.Equal((ArrKind.Radarr, 77, false, true), Assert.Single(_arr.RemoveFromQueueCalls));
        Assert.Equal("a", Assert.Single(_arr.GrabCalls).Guid);
        Assert.Equal((DownloadStates.Downloading, (string?)null), (Saved("movie:12")!.State, Saved("movie:12")!.Reason));
    }

    [Fact]
    public async Task OneGrabAtATime()
    {
        // L'admin scarica b: un altro admin trova Busy, il giro cerca ma non scarica.
        Animals();
        await Search("movie:12");
        var adminGrab = new TaskCompletionSource();
        _arr.Grab = (_, _, _) => adminGrab.Task;
        var first = Grab("movie:12", "b", 3);

        Assert.Equal(GrabOutcome.Busy, await Grab("movie:12", "a", 1));

        // Senza il controllo il giro aspetterebbe il grab dell'admin per sempre.
        await _service.RunCycleAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(2, _arr.SearchReleaseCalls.Count);
        Assert.Single(_arr.GrabCalls);
        adminGrab.SetResult();
        Assert.Equal(GrabOutcome.Ok, await first);

        // Il giro scarica Dune: l'admin trova Busy.
        _movies = [.. _movies, Movie(13, title: "Dune")];
        var cycleGrab = new TaskCompletionSource();
        _arr.Grab = (_, _, _) => cycleGrab.Task;
        var cycle = _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(2, _arr.GrabCalls.Count);

        Assert.Equal(GrabOutcome.Busy, await Grab("movie:13", "a", 1));
        cycleGrab.SetResult();
        await cycle;
        Assert.Equal(2, _arr.GrabCalls.Count);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:13")!.State);
    }

    [Fact]
    public async Task AnEpisodeIsReadWithOneCall()
    {
        // Severance S02E05 (42) con un profilo che Sonarr non ha più: nessuna release si importerebbe da sola.
        var episode = Episode(42, T0 - TimeSpan.FromDays(1));
        episode.Series!.QualityProfileId = 99;
        _arr.EpisodeById = _ => Task.FromResult(episode);
        _releases = [Release("e", WebDl1080, "WEBDL-1080p", 1, 150)];

        // Senza voce.
        var result = (await Search("episode:42"))!;
        Assert.Equal(("Severance · S02E05", DownloadKinds.Episode, 50, (string?)null), (result.Title, result.Kind, result.RuntimeMinutes, result.Error));
        Assert.Equal((ArrKind.Sonarr, "episodeId=42"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.False(Assert.Single(result.Candidates).WouldImport);

        // Senza un file non c'è niente da importare a mano.
        Assert.Equal(GrabOutcome.Ok, await Grab("episode:42", "e", 1));
        var entry = Saved("episode:42")!;
        Assert.Equal((DownloadStates.Downloading, 7, false), (entry.State, entry.SeriesId, entry.ManualImportPending));

        // "cambia": si toglie l'elemento dell'episodio, non quello di un altro.
        _sonarrQueue = [EpisodeQueue(55, 42, 5_000), EpisodeQueue(56, 41, 5_000)];
        Assert.Equal(GrabOutcome.Ok, await Grab("episode:42", "e", 1));
        Assert.Equal((ArrKind.Sonarr, 55, false, true), Assert.Single(_arr.RemoveFromQueueCalls));

        // Con la voce: sempre una chiamata, senza leggere le serie.
        await Search("episode:42");
        Assert.Equal([42, 42], _arr.EpisodeByIdCalls);
        Assert.Equal(0, _arr.SeriesCalls);
        Assert.Empty(_arr.SeriesEpisodeCalls);

        // Un episodio che Sonarr non ha (404).
        _arr.EpisodeById = _ => Task.FromException<SonarrEpisode>(new ArrException(ArrError.Unreachable, status: 404));
        Assert.Null(await Search("episode:43"));
    }

    [Fact]
    public async Task TheOverviewShowsTheLast90Days()
    {
        // Con i download spenti il giro non pota le scelte vecchie.
        _settings.Enabled = false;
        var book = new DownloadBook();
        book.AddChoice(new DownloadChoice { Key = "movie:12", Kind = DownloadKinds.Movie, Guid = "old", At = T0 - DownloadBook.ChoiceRetention - TimeSpan.FromDays(1) });
        book.AddChoice(new DownloadChoice { Key = "movie:13", Kind = DownloadKinds.Movie, Guid = "new", At = T0 - TimeSpan.FromDays(1) });
        Store().Save(book);

        Assert.Equal(["new"], (await _service.OverviewAsync(CancellationToken.None)).Recent.Select(c => c.Release.Guid));
    }

    [Fact]
    public async Task AGrabThatWouldNotImportIsFlagged()
    {
        AnimalsOnBluray();
        await Search("movie:12");

        Assert.Equal(GrabOutcome.Ok, await Grab("movie:12", "b", 3));

        var entry = Saved("movie:12")!;
        Assert.True(entry.ManualImportPending);
        Assert.Equal(((int?)0, (int?)Bluray1080, (long?)(12.4 * Gb)), (entry.PreviousScore, entry.PreviousQualityId, entry.PreviousSizeBytes));
        Assert.Equal(((int?)150, (long?)(1.89 * Gb)), (entry.CurrentScore, entry.CurrentSizeBytes));
        var choice = Assert.Single(Store().Load().Choices);
        Assert.Equal((true, (int?)0, (long?)(12.4 * Gb)), (choice.ByAdmin, choice.PreviousScore, choice.PreviousSizeBytes));
    }

    [Fact]
    public async Task ASeasonGrabKeepsItsEpisodes()
    {
        // Severance stagione 2: tre episodi già scaricati, il peggiore da 10 punti; la stagione 1 non conta.
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 7, Title = "Severance", Runtime = 50, QualityProfileId = 6 }]);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
            [.. new[] { 1, 2, 3 }.Select(n => (SonarrEpisode?)new SonarrEpisode { Id = 200 + n, SeriesId = 7, SeasonNumber = 2, EpisodeNumber = n, Monitored = true, HasFile = true, EpisodeFileId = 300 + n, AirDateUtc = T0 - TimeSpan.FromDays(30) })]);
        ArrFile SeasonFile(int id, int season, int qualityId, string quality, int score, double gb)
        {
            var file = File(id, qualityId, score);
            (file.SeasonNumber, file.Size, file.Quality!.Quality!.Name) = (season, (long)(gb * Gb), quality);
            return file;
        }

        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
        [
            SeasonFile(301, 2, WebRip1080, "WEBRip-1080p", 30, 2),
            SeasonFile(302, 2, WebDl1080, "WEBDL-1080p", 10, 3),
            SeasonFile(303, 2, WebRip1080, "WEBRip-1080p", 40, 2),
            SeasonFile(101, 1, Hdtv720, "HDTV-720p", 0, 1),
        ]);

        // Un pack da 8 GB per 150 minuti e un singolo da 1 GB per 50: valido, misurato sul suo episodio.
        var pack = Release("p", WebRip1080, "WEBRip-1080p", 8, 150);
        pack.FullSeason = true;
        var single = Release("s", WebRip1080, "WEBRip-1080p", 1, 150);
        single.EpisodeNumbers = [1];
        _releases = [pack, single];

        var result = (await Search("season:7:2"))!;

        Assert.Equal((ArrKind.Sonarr, "seriesId=7&seasonNumber=2"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.Equal(("Severance · Stagione 2", DownloadKinds.Season, 50), (result.Title, result.Kind, result.RuntimeMinutes));
        Assert.Equal(((long)(7 * Gb), 10, "WEBDL-1080p"), (result.Current!.SizeBytes, result.Current.Score, result.Current.Quality));
        Assert.Empty(result.Rejected);
        // La scelta della regola è la prima, anche se da sola il singolo verrebbe prima.
        Assert.Equal([("p", true, 1), ("s", false, 2)], result.Candidates.Select(c => (c.Release.Guid, c.IsChoice, c.Rank)));

        Assert.Equal(GrabOutcome.Ok, await Grab("season:7:2", "p", 1));
        var entry = Saved("season:7:2")!;
        Assert.Equal((DownloadKinds.Season, 7, "Severance · Stagione 2", (int?)10, (int?)WebDl1080, (long?)(7 * Gb)), (entry.Kind, entry.SeriesId, entry.Title, entry.PreviousScore, entry.PreviousQualityId, entry.PreviousSizeBytes));
        Assert.Equal([1, 2, 3], entry.EpisodeNumbers!);
        Assert.False(entry.ManualImportPending);

        // "cambia" con il singolo: si tolgono tutti gli elementi del pack in coda, non quelli della stagione 1.
        _sonarrQueue = [EpisodeQueue(61, 202, 5_000), EpisodeQueue(60, 201, 5_000), new ArrQueueItem { Id = 62, SeriesId = 7, SeasonNumber = 1 }];
        Assert.Equal(GrabOutcome.Ok, await Grab("season:7:2", "s", 1));
        Assert.Equal([60, 61], _arr.RemoveFromQueueCalls.Select(c => c.QueueId));

        // Il singolo è una voce di episodio, con il file di quell'episodio (ruling 13); la voce di stagione, che scaricava il pack, esce.
        var episode = Saved("episode:201")!;
        Assert.Equal((DownloadKinds.Episode, DownloadStates.Downloading, 7, (int?)30, (int?)WebRip1080, (long?)(2 * Gb)), (episode.Kind, episode.State, episode.SeriesId, episode.PreviousScore, episode.PreviousQualityId, episode.PreviousSizeBytes));
        Assert.Null(episode.EpisodeNumbers);
        Assert.Contains(("episode:201", "s"), Store().Load().Choices.Select(c => (c.Key, c.Guid)));
        Assert.Null(Saved("season:7:2"));
    }

    // Severance stagione 2 (50 minuti, profilo 6: obiettivo 150): un episodio per punteggio, null = manca. Il file pesa 2 GB.
    private void SeasonOf(params int?[] scores)
    {
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 7, Title = "Severance", Runtime = 50, QualityProfileId = 6 }]);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
            [.. scores.Select((score, i) => (SonarrEpisode?)new SonarrEpisode { Id = 201 + i, SeriesId = 7, SeasonNumber = 2, EpisodeNumber = i + 1, Monitored = true, HasFile = score is not null, EpisodeFileId = score is null ? 0 : 301 + i, AirDateUtc = T0 - TimeSpan.FromDays(30) })]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
            [.. scores.Select((score, i) => (ArrFile?)(score is null ? null : File(301 + i, WebRip1080, score.Value))).OfType<ArrFile>().Select(f => { f.SeasonNumber = 2; f.Size = 2 * Gb; f.Quality!.Quality!.Name = "WEBRip-1080p"; return (ArrFile?)f; })]);
    }

    private static ArrRelease Single(string guid, int episode, double gb, int score, int qualityId = WebRip1080, string quality = "WEBRip-1080p")
    {
        var release = Release(guid, qualityId, quality, gb, score);
        release.EpisodeNumbers = [episode];
        return release;
    }

    private static ArrRelease Pack(string guid, double gb, int score)
    {
        var release = Release(guid, WebRip1080, "WEBRip-1080p", gb, score);
        release.FullSeason = true;
        return release;
    }

    private static List<(int, string?, bool)> Flat(DownloadSearchDto result) =>
        [.. result.EpisodeChoices.Select(c => (c.EpisodeNumber, c.Release?.Guid, c.WouldImport))];

    [Fact]
    public async Task ASeasonWithoutAPackHasTheBestSinglePerMissingEpisode()
    {
        // Mancano 1, 2 e 3; il 4 c'è e non conta. Il 3 ha solo un singolo troppo leggero (0,2 GB in 50 minuti).
        SeasonOf(null, null, null, 150);
        _releases =
        [
            Single("s1a", 1, 1, 100),
            Single("s1b", 1, 1.2, 150),
            Single("s2", 2, 1, 150),
            Single("s3", 3, 0.2, 150),
            Single("s4", 4, 1, 150),
        ];

        var result = (await Search("season:7:2"))!;

        Assert.Equal([(1, "s1b", true), (2, "s2", true), (3, (string?)null, false)], Flat(result));
        Assert.Equal(("s1b", 150, (int?)10), (result.EpisodeChoices[0].Release!.Guid, result.EpisodeChoices[0].Release!.Score, result.EpisodeChoices[0].Release!.Seeders));

        // Il JSON del server salta i null: "Release" deve esserci lo stesso, e la lista anche per un film.
        var options = new System.Text.Json.JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull };
        Assert.All(result.EpisodeChoices, c => Assert.Null(c.CurrentScore));
        Assert.Contains("{\"EpisodeNumber\":3,\"Release\":null,\"WouldImport\":false,\"CurrentScore\":null}", System.Text.Json.JsonSerializer.Serialize(result, options));
    }

    [Fact]
    public async Task AnAnimeSingleWithOnlyMappedNumbersIsTheEpisodeChoice()
    {
        SeasonOf(null, null, null);
        var anime = Single("a3", 3, 1, 150);
        (anime.EpisodeNumbers, anime.MappedEpisodeNumbers) = ([], [3]);
        _releases = [anime];

        var result = (await Search("season:7:2"))!;

        Assert.Equal([(1, (string?)null, false), (2, (string?)null, false), (3, "a3", true)], Flat(result));
    }

    [Fact]
    public async Task APackTooHeavyForItsSinglesIsNotAChoice()
    {
        SeasonOf(null, null);
        _releases = [Pack("p", 20, 150), Single("s1", 1, 1, 150), Single("s2", 2, 1, 150)];

        var result = (await Search("season:7:2"))!;

        Assert.False(Assert.Single(result.Candidates, c => c.Release.Guid == "p").IsChoice);
        Assert.Equal([(1, "s1", true), (2, "s2", true)], Flat(result));
    }

    [Fact]
    public async Task AChosenPackLeavesNoEpisodeChoices()
    {
        // L'episodio 3 non ha singoli validi: il pack si prende e non c'è niente da scegliere episodio per episodio.
        SeasonOf(null, null, null);
        _releases = [Pack("p", 6, 150), Single("s1", 1, 1, 150), Single("s2", 2, 1, 150)];

        var result = (await Search("season:7:2"))!;

        Assert.True(Assert.Single(result.Candidates, c => c.Release.Guid == "p").IsChoice);
        Assert.Empty(result.EpisodeChoices);
    }

    [Fact]
    public async Task AMovieHasNoEpisodeChoices()
    {
        Animals();

        Assert.Empty((await Search("movie:12"))!.EpisodeChoices);
    }

    [Fact]
    public async Task AWholeSeasonWithoutMissingEpisodesChoosesTheOnesBelowTarget()
    {
        // Nessun episodio manca: contano quelli sotto l'obiettivo (150). Il file del 3 vale 90: un 60 non lo migliora,
        // anche se batte il peggiore della stagione (40).
        SeasonOf(150, 40, 90, 150);
        _releases = [Single("s1", 1, 1, 150), Single("s2", 2, 1, 60), Single("s3", 3, 1, 60), Single("s4", 4, 1, 150)];

        var result = (await Search("season:7:2"))!;

        Assert.Equal([(2, "s2", true), (3, "s3", false)], Flat(result));
        Assert.Equal([40, 90], result.EpisodeChoices.Select(c => c.CurrentScore));

        // Senza un obiettivo (profilo senza) tutti.
        _settings.Thresholds[(ArrKind.Sonarr, 6)] = new ProfileThresholds(50, null);
        Assert.Equal([1, 2, 3, 4], (await Search("season:7:2"))!.EpisodeChoices.Select(c => c.EpisodeNumber));
    }

    [Fact]
    public async Task WithoutMissingEpisodesOnlyMonitoredAiredOnesAreChoices()
    {
        // 1 a posto, 2 e 3 non monitorati (con e senza file), 4 e 5 non ancora usciti (con e senza file), 6 sotto l'obiettivo.
        SeasonOf(150, 40, null, 40, null, 40);
        var episodes = _arr.SeriesEpisodes;
        _arr.SeriesEpisodes = async id =>
        {
            var list = await episodes(id);
            list[1]!.Monitored = false;
            list[2]!.Monitored = false;
            list[3]!.AirDateUtc = T0 + TimeSpan.FromDays(3);
            list[4]!.AirDateUtc = T0 + TimeSpan.FromDays(3);
            return list;
        };
        _releases = [.. Enumerable.Range(1, 6).Select(n => Single("s" + n, n, 1, 150))];

        var result = (await Search("season:7:2"))!;

        Assert.Equal([6], result.EpisodeChoices.Select(c => c.EpisodeNumber));

        // Senza obiettivo tutti i monitorati e usciti, non gli altri.
        _settings.Thresholds[(ArrKind.Sonarr, 6)] = new ProfileThresholds(50, null);
        Assert.Equal([1, 6], (await Search("season:7:2"))!.EpisodeChoices.Select(c => c.EpisodeNumber));
    }

    [Fact]
    public async Task AWholeUnmonitoredSeasonUsesAllAiredEpisodes()
    {
        // Serie tolta dal monitoraggio in Sonarr: nessun episodio monitorato, contano tutti quelli usciti (il 3 non ancora).
        SeasonOf(40, 40, 40);
        var episodes = _arr.SeriesEpisodes;
        _arr.SeriesEpisodes = async id =>
        {
            var list = await episodes(id);
            foreach (var episode in list)
            {
                episode!.Monitored = false;
            }

            list[2]!.AirDateUtc = T0 + TimeSpan.FromDays(3);
            return list;
        };
        _releases = [.. Enumerable.Range(1, 3).Select(n => Single("s" + n, n, 1, 150))];

        Assert.Equal([1, 2], (await Search("season:7:2"))!.EpisodeChoices.Select(c => c.EpisodeNumber));
    }

    [Fact]
    public async Task TwoSingleGrabsFromTheSameSeasonSearchBothStart()
    {
        SeasonOf(null, null, null);
        _releases = [Single("s1", 1, 1, 150), Single("s2", 2, 1, 150), Single("s3", 3, 1, 150)];
        await Search("season:7:2");

        Assert.Equal(GrabOutcome.Ok, await Grab("season:7:2", "s1", 1));

        // Il primo sta già in coda: il secondo non lo deve togliere.
        _sonarrQueue = [EpisodeQueue(70, 201, 5_000)];
        Assert.Equal(GrabOutcome.Ok, await Grab("season:7:2", "s2", 1));

        Assert.Equal(["s1", "s2"], _arr.GrabCalls.Select(c => c.Guid));
        Assert.Empty(_arr.RemoveFromQueueCalls);
        Assert.Single(_arr.SearchReleaseCalls);
        Assert.Equal((DownloadStates.Downloading, DownloadStates.Downloading), (Saved("episode:201")!.State, Saved("episode:202")!.State));
        Assert.Equal(["episode:201", "episode:202"], Store().Load().Choices.Select(c => c.Key));
    }

    [Fact]
    public async Task AcceptHidesFromReview()
    {
        ReviewOf("movie:12", "movie:13");
        Assert.Equal(["movie:12", "movie:13"], (await _service.OverviewAsync(CancellationToken.None)).Review.Select(r => r.Key));

        Assert.True(_service.Accept("movie:12"));

        Assert.Equal(["movie:13"], (await _service.OverviewAsync(CancellationToken.None)).Review.Select(r => r.Key));
        Assert.Equal(["movie:12"], Store().Load().ToFile().Accepted);
    }

    [Fact]
    public async Task SearchNowNudges()
    {
        Animals();
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.True(Saved("movie:12")!.NextSearchAt > T0);
        var nudges = 0;
        _service.Nudged += () => nudges++;

        _time.Advance(TimeSpan.FromMinutes(1));
        Assert.True(_service.SearchNow("movie:12"));

        Assert.Equal((T0 + TimeSpan.FromMinutes(1), 1), (Saved("movie:12")!.NextSearchAt, nudges));
    }

    private async Task<string?> PhaseOf(string key) => (await _service.OverviewAsync(CancellationToken.None)).Waiting.Single(i => i.Key == key).SearchPhase;

    [Fact]
    public async Task SearchNowShowsQueued()
    {
        Animals();
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Null(await PhaseOf("movie:12"));

        Assert.True(_service.SearchNow("movie:12"));

        Assert.Equal(DownloadSearchPhases.Queued, await PhaseOf("movie:12"));
    }

    [Fact]
    public async Task ASearchInProgressShowsSearching()
    {
        Animals();
        var gate = new TaskCompletionSource<IReadOnlyList<ArrRelease?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _arr.Releases = (_, _) => gate.Task;

        var cycle = _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal(DownloadSearchPhases.Searching, await PhaseOf("movie:12"));
        gate.SetResult([]);
        await cycle;
        Assert.Null(await PhaseOf("movie:12"));
    }

    [Fact]
    public async Task NoPhaseWhenDisabled()
    {
        Animals();
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([]);
        await _service.RunCycleAsync(CancellationToken.None);
        _service.SearchNow("movie:12");
        _settings.Enabled = false;

        Assert.Null(await PhaseOf("movie:12"));
    }

    [Fact]
    public async Task ImportBlockedIsNeverQueued()
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "movie:12", Kind = DownloadKinds.Movie, Title = "Animals (2025)", State = DownloadStates.NeedsYou, Reason = DownloadReasons.ImportBlocked, QueueId = 77, AvailableSince = T0, NextSearchAt = T0 });
        Store().Save(book);

        Assert.Null(await PhaseOf("movie:12"));
    }

    [Fact]
    public async Task ProfilesHaveTheirThresholds()
    {
        _settings.Thresholds[(ArrKind.Radarr, 4)] = new ProfileThresholds(60, 200);
        _arr.QualityProfiles = kind => kind == ArrKind.Radarr
            ? Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), new ArrQualityProfile { Id = 9, Name = "Radarr Anime" }])
            : Task.FromException<IReadOnlyList<ArrQualityProfile?>>(new ArrException(ArrError.Unreachable));

        var profiles = await _service.ProfilesAsync(CancellationToken.None);

        Assert.Equal(
            [("Radarr", 4, "Main", 60, (int?)200), ("Radarr", 9, "Radarr Anime", 1, (int?)null)],
            profiles!.Select(p => (p.Service, p.ProfileId, p.Name, p.MinScore, p.TargetScore)));

        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(6)]);
        profiles = await _service.ProfilesAsync(CancellationToken.None);
        Assert.Equal([("Radarr", 6, 50, (int?)150), ("Sonarr", 6, 50, (int?)150)], profiles!.Select(p => (p.Service, p.ProfileId, p.MinScore, p.TargetScore)));

        // Tutti e due in errore: null, non un elenco vuoto (ruling 14); nessuno configurato: vuoto.
        _arr.QualityProfiles = _ => Task.FromException<IReadOnlyList<ArrQualityProfile?>>(new ArrException(ArrError.Unreachable));
        Assert.Null(await _service.ProfilesAsync(CancellationToken.None));
        (_arrSettings.Radarr, _arrSettings.Sonarr) = (ArrEndpoint.None, ArrEndpoint.None);
        Assert.Empty((await _service.ProfilesAsync(CancellationToken.None))!);
    }

    private static (string, int, string, string, string, int, long, int, int?) Flat(DownloadReleaseDto r) =>
        (r.Guid, r.IndexerId, r.Indexer, r.Title, r.Quality, r.Resolution, r.SizeBytes, r.Score, r.Seeders);

    // Animals in "Serve te" per un motivo; il film è in Radarr senza file.
    private void NeedsYou(string reason, Action<DownloadEntry>? change = null)
    {
        _movies = [Movie(12, title: "Animals", year: 2025, runtime: 106)];
        var entry = new DownloadEntry
        {
            Key = "movie:12",
            Kind = DownloadKinds.Movie,
            Title = "Animals (2025)",
            State = DownloadStates.NeedsYou,
            Reason = reason,
            ProfileId = 4,
            RuntimeMinutes = 106,
            AvailableSince = T0 - TimeSpan.FromDays(10),
            NextSearchAt = T0 + TimeSpan.FromDays(1),
        };
        change?.Invoke(entry);
        var book = new DownloadBook();
        book.Put(entry);
        Store().Save(book);
    }

    private Task<GrabOutcome> GrabBest(string key = "movie:12") => _service.GrabBestAsync(key);

    [Fact]
    public async Task TheOverviewCarriesActionsAndSummary()
    {
        NeedsYou(DownloadReasons.NothingFound, e =>
        {
            e.Snoozed = true;
            e.BlockedMessage = "vecchio messaggio";
            e.Summary = new DownloadSummary { Found = 4, BestScore = 20, MinScore = 50, TooSmall = 1, ArrRejected = 2, TopRejection = "Not an upgrade", StopgapAvailable = true };
        });

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.True(item.Snoozed);
        Assert.Equal(["GrabBest", "Pick", "SearchNow", "Snooze"], item.Actions);
        Assert.Equal((4, (int?)20, 50, 1, 2, "Not an upgrade", true), (item.Summary!.Found, item.Summary.BestScore, item.Summary.MinScore, item.Summary.TooSmall, item.Summary.ArrRejected, item.Summary.TopRejection, item.Summary.StopgapAvailable));
        Assert.Null(item.BlockedMessage); // il messaggio vecchio non esce se il motivo non è ImportBlocked
        var json = System.Text.Json.JsonSerializer.Serialize(item, new System.Text.Json.JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull });
        Assert.Contains("\"Actions\"", json);
        Assert.Contains("\"Summary\"", json);
        Assert.Contains("\"BlockedMessage\":null", json);
    }

    private const string External = "https://t.example/?q={query}";

    [Theory]
    [InlineData(DownloadReasons.NothingFound)]
    [InlineData(DownloadReasons.BelowMinScore)]
    public async Task NothingUsableOffersTheExternalSearchLast(string reason)
    {
        _settings.ExternalSearchUrl = External;
        NeedsYou(reason);

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.Equal("ExternalSearch", item.Actions[^1]);
        Assert.Equal("https://t.example/?q=Animals", item.ExternalSearchUrl);
    }

    [Fact]
    public async Task AnotherReasonHasNoExternalSearch()
    {
        _settings.ExternalSearchUrl = External;
        NeedsYou(DownloadReasons.SearchFailed);

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.DoesNotContain("ExternalSearch", item.Actions);
        Assert.Null(item.ExternalSearchUrl);
        var json = System.Text.Json.JsonSerializer.Serialize(item, new System.Text.Json.JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull });
        Assert.Contains("\"ExternalSearchUrl\":null", json);
    }

    [Fact]
    public async Task AnEmptyLinkHasNoExternalSearch()
    {
        NeedsYou(DownloadReasons.NothingFound);

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.DoesNotContain("ExternalSearch", item.Actions);
        Assert.Null(item.ExternalSearchUrl);
    }

    [Fact]
    public async Task TheSearchCarriesTheExternalLink()
    {
        _settings.ExternalSearchUrl = External;
        Animals();

        Assert.Equal("https://t.example/?q=Animals", (await Search("movie:12"))!.ExternalSearchUrl);
    }

    [Fact]
    public async Task GrabBestTakesTheBestBelowMinimumAndMarksAStopgap()
    {
        NeedsYou(DownloadReasons.BelowMinScore);
        _releases = [Release("x30", WebRip1080, "WEBRip-1080p", 2, 30), Release("x40", WebRip1080, "WEBRip-1080p", 2, 40)];

        Assert.Equal(GrabOutcome.Ok, await GrabBest());

        Assert.Equal("x40", Assert.Single(_arr.GrabCalls).Guid);
        Assert.Single(_arr.SearchReleaseCalls);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, DownloadStopgaps.Score), (entry.State, entry.Stopgap));
    }

    [Fact]
    public async Task GrabBestTakesTheHeaviestTooSmall()
    {
        // Tutti sotto 0,8 GB all'ora (106 minuti): il più pesante.
        NeedsYou(DownloadReasons.NothingFound, e => e.Summary = new DownloadSummary { Found = 3, StopgapAvailable = true });
        _releases = [Release("s09", WebRip1080, "WEBRip-1080p", 0.9, 150), Release("s11", WebRip1080, "WEBRip-1080p", 1.1, 150), Release("arr", WebRip1080, "WEBRip-1080p", 5, 150)];
        _releases[2]!.Rejections = ["Unknown language"];

        Assert.Equal(GrabOutcome.Ok, await GrabBest());

        Assert.Equal("s11", Assert.Single(_arr.GrabCalls).Guid);
        Assert.Equal(DownloadStopgaps.Size, Saved("movie:12")!.Stopgap);
    }

    [Fact]
    public async Task GrabBestSkipsRefusedReleases()
    {
        NeedsYou(DownloadReasons.BelowMinScore, e => e.RefusedReleases = [DownloadRule.ReleaseId("x40", 1)]);
        _releases = [Release("x40", WebRip1080, "WEBRip-1080p", 2, 40), Release("x30", WebRip1080, "WEBRip-1080p", 2, 30)];

        Assert.Equal(GrabOutcome.Ok, await GrabBest());

        Assert.Equal("x30", Assert.Single(_arr.GrabCalls).Guid);
    }

    [Fact]
    public async Task GrabBestWithNothingToTakeSaysSo()
    {
        NeedsYou(DownloadReasons.NothingFound, e => e.Summary = new DownloadSummary { Found = 1, StopgapAvailable = true });
        _releases = [Release("arr", WebRip1080, "WEBRip-1080p", 5, 150)];
        _releases[0]!.Rejections = ["Unknown language"];

        Assert.Equal(GrabOutcome.NothingToGrab, await GrabBest());
        Assert.Empty(_arr.GrabCalls);

        // Una stagione o una chiave non valida: Invalid, senza cercare.
        Assert.Equal(GrabOutcome.Invalid, await GrabBest("season:7:2"));
        Assert.Equal(GrabOutcome.Invalid, await GrabBest("film:12"));
        Assert.Single(_arr.SearchReleaseCalls);
    }

    [Fact]
    public async Task GrabBestSearchesWithoutTheRequestToken()
    {
        // L'app chiusa o la rete caduta durante la ricerca: il download deve partire lo stesso.
        NeedsYou(DownloadReasons.BelowMinScore);
        _releases = [Release("x40", WebRip1080, "WEBRip-1080p", 2, 40)];

        Assert.Equal(GrabOutcome.Ok, await GrabBest());

        Assert.False(_arr.LastReleaseToken.CanBeCanceled);
    }

    [Fact]
    public async Task GrabBestWhileTheCycleGrabsIsBusy()
    {
        // Un altro grab dello stesso titolo è in corso.
        NeedsYou(DownloadReasons.BelowMinScore);
        _releases = [Release("x40", WebRip1080, "WEBRip-1080p", 2, 40)];
        var gate = new TaskCompletionSource();
        _arr.Grab = (_, _, _) => gate.Task;
        var first = Grab("movie:12", "x40", 1);

        Assert.Equal(GrabOutcome.Busy, await GrabBest());

        gate.SetResult();
        Assert.Equal(GrabOutcome.Ok, await first);
        Assert.Single(_arr.GrabCalls);
        Assert.Null(Saved("movie:12")!.Stopgap);
    }

    [Theory]
    [InlineData(DownloadStates.Downloading)]
    [InlineData(DownloadStates.UpgradeWatch)]
    public async Task GrabBestLeavesADownloadOrAnUpgradeWatchAlone(string state)
    {
        // La panoramica era vecchia (o un altro admin ha già premuto): la voce non è più in "Serve te".
        NeedsYou(DownloadReasons.BelowMinScore, e => (e.State, e.Reason, e.QueueId) = (state, null, 77));
        _radarrQueue = [MovieQueue(77, 12, 5_000)];
        _releases = [Release("x40", WebRip1080, "WEBRip-1080p", 2, 40), Release("ok", WebRip1080, "WEBRip-1080p", 4, 150)];

        Assert.Equal(GrabOutcome.NothingToGrab, await GrabBest());

        Assert.Empty(_arr.RemoveFromQueueCalls);
        Assert.Empty(_arr.GrabCalls);
        Assert.Equal(state, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task GrabBestRemembersARefusedRelease()
    {
        NeedsYou(DownloadReasons.BelowMinScore);
        _releases = [Release("x40", WebRip1080, "WEBRip-1080p", 2, 40), Release("x30", WebRip1080, "WEBRip-1080p", 2, 30)];
        _arr.Grab = (_, guid, _) => guid == "x40" ? Task.FromException(new ArrException(ArrError.Unreachable, status: 500)) : Task.CompletedTask;

        Assert.Equal(GrabOutcome.Refused, await GrabBest());
        Assert.Equal([DownloadRule.ReleaseId("x40", 1)], Saved("movie:12")!.RefusedReleases);

        // Alla seconda pressione la release rifiutata non si riprova.
        Assert.Equal(GrabOutcome.Ok, await GrabBest());
        Assert.Equal(["x40", "x30"], _arr.GrabCalls.Select(c => c.Guid));
    }

    [Fact]
    public void SnoozeMovesNothingFoundToWaiting()
    {
        NeedsYou(DownloadReasons.NothingFound);
        var nudges = 0;
        _service.Nudged += () => nudges++;

        Assert.True(_service.Snooze("movie:12"));

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, true, DownloadReasons.NothingFound, T0 + TimeSpan.FromDays(7)), (entry.State, entry.Snoozed, entry.Reason, entry.NextSearchAt));
        Assert.Empty(_service.NeedsYouAlerts());

        // Un giro presto: l'avviso esce dalla cassetta degli admin (spec §4.3).
        Assert.Equal(1, nudges);
    }

    [Fact]
    public void SnoozeRefusesOtherStates()
    {
        NeedsYou(DownloadReasons.BelowMinScore);

        Assert.False(_service.Snooze("movie:12"));
        Assert.False(_service.Snooze("movie:13"));
        Assert.False(_service.Snooze("film:12"));
        Assert.Equal((DownloadStates.NeedsYou, false), (Saved("movie:12")!.State, Saved("movie:12")!.Snoozed));
    }

    private void Blocked(Action<DownloadEntry>? change = null) =>
        NeedsYou(DownloadReasons.ImportBlocked, e =>
        {
            (e.QueueId, e.DownloadId, e.BlockedMessage) = (77, "abc", "Not an upgrade");
            change?.Invoke(e);
        });

    [Fact]
    public async Task ImportBlockedStartsTheManualImport()
    {
        Blocked();
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [new ArrManualImportItem { Path = "/dl/a.mkv", DownloadId = "abc", Movie = new ArrFileRef { Id = 12 }, Quality = System.Text.Json.JsonDocument.Parse("""{"quality":{"id":15}}""").RootElement, Rejections = [] }]);
        var nudges = 0;
        _service.Nudged += () => nudges++;

        Assert.Equal((BlockedOutcome.Ok, (string?)null), await _service.ImportBlockedAsync("movie:12"));

        Assert.Equal((ArrKind.Radarr, "abc"), Assert.Single(_arr.ManualImportReadCalls));
        Assert.Single(_arr.ManualImportCalls);
        Assert.Equal((DownloadStates.Downloading, (string?)null, 1), (Saved("movie:12")!.State, Saved("movie:12")!.Reason, nudges));
    }

    [Fact]
    public async Task AnAdminImportIsNotBlockedAgainWithinACycle()
    {
        Blocked();
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [new ArrManualImportItem { Path = "/dl/a.mkv", DownloadId = "abc", Movie = new ArrFileRef { Id = 12 }, Quality = System.Text.Json.JsonDocument.Parse("""{"quality":{"id":15}}""").RootElement, Rejections = [] }]);
        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportBlockedAsync("movie:12")).Outcome);

        // Il giro chiesto dopo l'import vede ancora la coda vecchia: la voce resta in download.
        var blocked = MovieQueue(77, 12, 0, state: "importBlocked", status: "completed");
        blocked.DownloadId = "abc";
        _radarrQueue = [blocked];
        _time.Advance(TimeSpan.FromMinutes(1));
        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);

        // Passato un giro intero ancora bloccato: serve di nuovo l'admin.
        _time.Advance(DownloadService.CycleInterval);
        await _service.RunCycleAsync(CancellationToken.None);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, (string?)DownloadReasons.ImportBlocked, (DateTimeOffset?)null), (entry.State, entry.Reason, entry.AdminImportAt));
    }

    [Fact]
    public async Task ImportBlockedReportsNoFiles()
    {
        Blocked();

        Assert.Equal((BlockedOutcome.Failed, (string?)"NoFiles"), await _service.ImportBlockedAsync("movie:12"));

        Assert.Empty(_arr.ManualImportCalls);
        Assert.Equal((DownloadStates.NeedsYou, (string?)DownloadReasons.ImportBlocked), (Saved("movie:12")!.State, Saved("movie:12")!.Reason));
    }

    [Fact]
    public async Task ImportBlockedOnAnotherStateIsChanged()
    {
        NeedsYou(DownloadReasons.BelowMinScore);
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportBlockedAsync("movie:12")).Outcome);
        Assert.Equal(BlockedOutcome.Changed, await _service.DiscardBlockedAsync("movie:12"));
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportBlockedAsync("movie:13")).Outcome);
        Assert.Equal(BlockedOutcome.Invalid, (await _service.ImportBlockedAsync("film:12")).Outcome);
        Assert.Equal(BlockedOutcome.Invalid, await _service.DiscardBlockedAsync("film:12"));
        Assert.Empty(_arr.ManualImportReadCalls);
        Assert.Empty(_arr.RemoveFromQueueCalls);
    }

    [Fact]
    public async Task ImportBlockedWithoutADownloadIsChanged()
    {
        // Bloccato ma senza il download da importare (scritto prima che il servizio legga il file).
        Blocked(e => e.DownloadId = null);

        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportBlockedAsync("movie:12")).Outcome);

        Assert.Empty(_arr.ManualImportReadCalls);
        Assert.Equal(DownloadStates.NeedsYou, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task DiscardWhileAnImportOfTheSameKeyRunsIsChanged()
    {
        Blocked();
        _radarrQueue = [MovieQueue(77, 12, 0, state: "importBlocked", status: "completed")];
        var gate = new TaskCompletionSource<IReadOnlyList<ArrManualImportItem?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _arr.ManualImportItems = (_, _) => gate.Task;
        var import = _service.ImportBlockedAsync("movie:12");

        Assert.Equal(BlockedOutcome.Changed, await _service.DiscardBlockedAsync("movie:12"));
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportBlockedAsync("movie:12")).Outcome);
        Assert.Empty(_arr.RemoveFromQueueCalls);

        // L'import non trova file: la chiave si libera e lo scarto ora passa.
        gate.SetResult([]);
        Assert.Equal((BlockedOutcome.Failed, (string?)"NoFiles"), await import);
        Assert.Single(_arr.ManualImportReadCalls);
        Assert.Equal(BlockedOutcome.Ok, await _service.DiscardBlockedAsync("movie:12"));
    }

    [Fact]
    public async Task DiscardRemovesWithBlocklistAndSearchesAgain()
    {
        Blocked();
        var blocked = MovieQueue(77, 12, 0, state: "importBlocked", status: "completed");
        blocked.DownloadId = "abc";
        _radarrQueue = [blocked];
        var nudges = 0;
        _service.Nudged += () => nudges++;

        Assert.Equal(BlockedOutcome.Ok, await _service.DiscardBlockedAsync("movie:12"));

        Assert.Equal((ArrKind.Radarr, 77, true, true), Assert.Single(_arr.RemoveFromQueueCalls));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (string?)null, T0, 1), (entry.State, entry.Reason, entry.NextSearchAt, nudges));
        Assert.Equal(((string?)null, (string?)null), (entry.DownloadId, entry.BlockedMessage));
    }

    [Fact]
    public async Task DiscardOfAnUpgradeGoesBackToUpgradeWatch()
    {
        Blocked(e =>
        {
            (e.CurrentScore, e.CurrentQualityId, e.CurrentSizeBytes) = (150, WebRip1080, 2 * Gb);
            (e.PreviousScore, e.PreviousQualityId, e.PreviousSizeBytes) = (0, Bluray1080, 12 * Gb);
            e.UpgradeUntil = T0 + TimeSpan.FromDays(20);
        });
        _radarrQueue = [MovieQueue(77, 12, 0, state: "importBlocked", status: "completed")];

        Assert.Equal(BlockedOutcome.Ok, await _service.DiscardBlockedAsync("movie:12"));

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.UpgradeWatch, (int?)0, (int?)Bluray1080, (long?)(12 * Gb), (int?)null, T0), (entry.State, entry.CurrentScore, entry.CurrentQualityId, entry.CurrentSizeBytes, entry.PreviousScore, entry.NextSearchAt));
    }

    // Un download fermo sui metadati: in coda da T0.
    private void FetchingMetadata(Action<DownloadEntry>? change = null)
    {
        var book = new DownloadBook();
        var entry = new DownloadEntry
        {
            Key = "movie:12", Kind = DownloadKinds.Movie, Title = "Dune", State = DownloadStates.Downloading, AvailableSince = T0,
            NextSearchAt = T0 + TimeSpan.FromDays(1), QueueId = 77, MetadataSince = T0 - TimeSpan.FromHours(2),
        };
        change?.Invoke(entry);
        book.Put(entry);
        Store().Save(book);
    }

    [Fact]
    public async Task DiscardWorksWhileFetchingMetadata()
    {
        FetchingMetadata();
        _radarrQueue = [MetadataQueue(77, 12)];
        var nudges = 0;
        _service.Nudged += () => nudges++;

        Assert.Equal(BlockedOutcome.Ok, await _service.DiscardBlockedAsync("movie:12"));

        Assert.Equal((ArrKind.Radarr, 77, true, true), Assert.Single(_arr.RemoveFromQueueCalls));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Waiting, (int?)null, (DateTimeOffset?)null, T0, 1), (entry.State, entry.QueueId, entry.MetadataSince, entry.NextSearchAt, nudges));
    }

    [Fact]
    public async Task DiscardOfAPlainDownloadIsChanged()
    {
        FetchingMetadata(e => e.MetadataSince = null);
        _radarrQueue = [MovieQueue(77, 12, 5_000)];

        Assert.Equal(BlockedOutcome.Changed, await _service.DiscardBlockedAsync("movie:12"));

        Assert.Empty(_arr.RemoveFromQueueCalls);
        Assert.Equal(DownloadStates.Downloading, Saved("movie:12")!.State);
    }

    [Fact]
    public async Task TheOverviewMarksAMetadataFetch()
    {
        FetchingMetadata();
        _radarrQueue = [MetadataQueue(77, 12)];

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.Equal(new DownloadProgressDto(0, 0, null, "metadata", T0 - TimeSpan.FromHours(2)), item.Progress);
        Assert.Equal(["Pick", "SearchNow", "Discard"], item.Actions);
    }

    // Una voce in download, scritta prima che il servizio legga il file.
    private void Downloading(string key, string kind, string state = DownloadStates.Downloading)
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = key, Kind = kind, Title = key, State = state, AvailableSince = T0, NextSearchAt = T0 + TimeSpan.FromDays(1) });
        Store().Save(book);
    }

    [Fact]
    public async Task TheOverviewCarriesDownloadProgress()
    {
        Downloading("movie:12", DownloadKinds.Movie);
        var eta = T0 + TimeSpan.FromMinutes(20);
        _radarrQueue = [new ArrQueueItem { Id = 1, MovieId = 12, DownloadId = "D", Size = 3_000_000_000, Sizeleft = 1_200_000_000, EstimatedCompletionTime = eta, Status = "downloading", TrackedDownloadState = "downloading" }];

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.Equal(new DownloadProgressDto(3_000_000_000, 1_200_000_000, eta, "downloading"), item.Progress);
    }

    [Fact]
    public async Task AWaitingEntryHasNoProgress()
    {
        Downloading("movie:12", DownloadKinds.Movie, DownloadStates.Waiting);
        _radarrQueue = [MovieQueue(1, 12, 100)];

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.Null(item.Progress);
        Assert.Empty(_arr.QueueCalls);
    }

    [Fact]
    public async Task ASeasonPackHasOneProgress()
    {
        Downloading("season:7:2", DownloadKinds.Season);
        var (early, late) = (T0 + TimeSpan.FromMinutes(5), T0 + TimeSpan.FromMinutes(9));
        _sonarrQueue =
        [
            new ArrQueueItem { Id = 1, EpisodeId = 1, SeriesId = 7, SeasonNumber = 2, DownloadId = "P", Size = 8_000, Sizeleft = 4_000, EstimatedCompletionTime = early, Status = "queued" },
            new ArrQueueItem { Id = 2, EpisodeId = 2, SeriesId = 7, SeasonNumber = 2, DownloadId = "P", Size = 8_000, Sizeleft = 4_000, EstimatedCompletionTime = late, Status = "downloading" },
        ];

        var item = Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Waiting);

        Assert.Equal(new DownloadProgressDto(8_000, 4_000, late, "downloading"), item.Progress);
    }

    [Fact]
    public async Task TheQueueIsReadAtMostOncePerMinute()
    {
        Downloading("movie:12", DownloadKinds.Movie);
        _radarrQueue = [MovieQueue(1, 12, 100)];

        await _service.OverviewAsync(CancellationToken.None);
        _time.Advance(TimeSpan.FromSeconds(30));
        await _service.OverviewAsync(CancellationToken.None);
        Assert.Single(_arr.QueueCalls);

        _time.Advance(TimeSpan.FromSeconds(31));
        await _service.OverviewAsync(CancellationToken.None);
        Assert.Equal(2, _arr.QueueCalls.Count);
    }

    [Fact]
    public async Task AQueueErrorLeavesProgressEmpty()
    {
        Downloading("movie:12", DownloadKinds.Movie);
        _arr.Queue = _ => Task.FromException<IReadOnlyList<ArrQueueItem?>>(new ArrException(ArrError.Unreachable));

        var overview = await _service.OverviewAsync(CancellationToken.None);

        var item = Assert.Single(overview.Waiting);
        Assert.Equal(("movie:12", DownloadStates.Downloading), (item.Key, item.State));
        Assert.Null(item.Progress);
    }
}
