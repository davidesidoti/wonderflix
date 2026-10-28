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
        var overview = _service.Overview();
        Assert.Equal(["movie:13"], overview.Review.Select(r => r.Key));
        Assert.Empty(Store().Load().ToFile().Accepted);
        var recent = Assert.Single(overview.Recent);
        Assert.Equal(("movie:12", "Animals (2025)", "b", true), (recent.Key, recent.Title, recent.Release.Guid, recent.ByAdmin));
        var waiting = Assert.Single(overview.Waiting);
        Assert.Equal(("movie:12", DownloadStates.Downloading, T0), (waiting.Key, waiting.State, waiting.AvailableSince));
        Assert.True(overview.Enabled);
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

        // Il client di download giù (500): né Expired né una voce nuova.
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>(_releases);
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));
        Assert.Equal(GrabOutcome.Unavailable, await Grab("movie:12", "b", 3));
        Assert.Single(_arr.GrabCalls);
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
        Assert.Equal((ArrKind.Radarr, 77, false), Assert.Single(_arr.RemoveFromQueueCalls));
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

        Assert.Equal((ArrKind.Radarr, 78, false), Assert.Single(_arr.RemoveFromQueueCalls));
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

        Assert.Equal((ArrKind.Radarr, 77, false), Assert.Single(_arr.RemoveFromQueueCalls));
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
        Assert.Equal((ArrKind.Sonarr, 55, false), Assert.Single(_arr.RemoveFromQueueCalls));

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
    public void TheOverviewShowsTheLast90Days()
    {
        // Con i download spenti il giro non pota le scelte vecchie.
        _settings.Enabled = false;
        var book = new DownloadBook();
        book.AddChoice(new DownloadChoice { Key = "movie:12", Kind = DownloadKinds.Movie, Guid = "old", At = T0 - DownloadBook.ChoiceRetention - TimeSpan.FromDays(1) });
        book.AddChoice(new DownloadChoice { Key = "movie:13", Kind = DownloadKinds.Movie, Guid = "new", At = T0 - TimeSpan.FromDays(1) });
        Store().Save(book);

        Assert.Equal(["new"], _service.Overview().Recent.Select(c => c.Release.Guid));
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

        // "cambia": si tolgono tutti gli elementi del pack in coda, non quelli della stagione 1.
        _sonarrQueue = [EpisodeQueue(61, 202, 5_000), EpisodeQueue(60, 201, 5_000), new ArrQueueItem { Id = 62, SeriesId = 7, SeasonNumber = 1 }];
        Assert.Equal(GrabOutcome.Ok, await Grab("season:7:2", "s", 1));
        Assert.Equal([60, 61], _arr.RemoveFromQueueCalls.Select(c => c.QueueId));
        Assert.Equal([1], Saved("season:7:2")!.EpisodeNumbers!);
    }

    [Fact]
    public void AcceptHidesFromReview()
    {
        ReviewOf("movie:12", "movie:13");
        Assert.Equal(["movie:12", "movie:13"], _service.Overview().Review.Select(r => r.Key));

        Assert.True(_service.Accept("movie:12"));

        Assert.Equal(["movie:13"], _service.Overview().Review.Select(r => r.Key));
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
            profiles.Select(p => (p.Service, p.ProfileId, p.Name, p.MinScore, p.TargetScore)));

        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(6)]);
        profiles = await _service.ProfilesAsync(CancellationToken.None);
        Assert.Equal([("Radarr", 6, 50, (int?)150), ("Sonarr", 6, 50, (int?)150)], profiles.Select(p => (p.Service, p.ProfileId, p.MinScore, p.TargetScore)));
    }

    private static (string, int, string, string, string, int, long, int, int?) Flat(DownloadReleaseDto r) =>
        (r.Guid, r.IndexerId, r.Indexer, r.Title, r.Quality, r.Resolution, r.SizeBytes, r.Score, r.Seeders);
}
