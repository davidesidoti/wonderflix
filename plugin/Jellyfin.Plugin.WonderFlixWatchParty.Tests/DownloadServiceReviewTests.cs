using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadServiceReviewTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeArrSettings _arrSettings = new();
    private readonly FakeDownloadSettings _settings = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    private List<RadarrMovie?> _movies = [];
    private List<ArrFile?> _movieFiles = [];
    private List<ArrQueueItem?> _radarrQueue = [];
    private List<ArrQueueItem?> _sonarrQueue = [];

    public DownloadServiceReviewTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>(_movies);
        _arr.MovieFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(_movieFiles);
        _arr.Queue = kind => Task.FromResult<IReadOnlyList<ArrQueueItem?>>(kind == ArrKind.Radarr ? _radarrQueue : _sonarrQueue);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4), MainProfile(6)]);

        // Niente Load(): un test può scrivere downloads.json prima che il servizio lo legga.
        _service = new DownloadService(_arr, _arrSettings, _settings, Store(), _time, NullLogger<DownloadService>.Instance) { Pause = TimeSpan.Zero };
    }

    public void Dispose() => _folder.Dispose();

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private DownloadEntry? Saved(string key) => Store().Load().Get(key);

    private Task Build() => _service.BuildReviewAsync(CancellationToken.None);

    private static ArrFile MovieFile(int movieId, int qualityId, string quality, int score, double gb)
    {
        var file = File(500 + movieId, qualityId, score);
        (file.MovieId, file.Size, file.Quality!.Quality!.Name) = (movieId, (long)(gb * Gb), quality);
        return file;
    }

    private static ArrFile EpisodeFile(int season, int qualityId, string quality, int score, double gb)
    {
        var file = File(0, qualityId, score);
        (file.SeasonNumber, file.Size, file.Quality!.Quality!.Name) = (season, (long)(gb * Gb), quality);
        return file;
    }

    private static ArrManualImportItem ImportItem(string path, int? movieId, string? rejection = null) => new()
    {
        Path = path,
        DownloadId = "D1",
        Movie = movieId is { } id ? new ArrFileRef { Id = id } : null,
        Quality = JsonDocument.Parse("""{"quality":{"id":7}}""").RootElement,
        Languages = JsonDocument.Parse("""[{"id":1}]""").RootElement,
        Rejections = rejection is null ? [] : [new ArrRejection { Reason = rejection }],
    };

    // Una release scelta dall'admin che Radarr non importerebbe, finita e bloccata in coda.
    private void AdminGrabBlocked(int movieId, int queueId, string downloadId)
    {
        var book = SavedBook() ?? new DownloadBook();
        book.Put(new DownloadEntry
        {
            Key = $"movie:{movieId}",
            Kind = DownloadKinds.Movie,
            State = DownloadStates.Downloading,
            AvailableSince = T0,
            QueueId = queueId,
            CurrentScore = 150,
            PreviousScore = 0,
            ManualImportPending = true,
        });
        Store().Save(book);
        _movies.Add(Movie(movieId, hasFile: true));
        var item = MovieQueue(queueId, movieId, 0, state: "importBlocked", status: "completed");
        item.DownloadId = downloadId;
        _radarrQueue.Add(item);
    }

    private DownloadBook? SavedBook() => System.IO.File.Exists(_folder.DownloadsFile) ? Store().Load() : null;

    [Fact]
    public async Task FilesBelowTargetAreListed()
    {
        _movies =
        [
            Movie(12, hasFile: true, title: "Amistad", year: 1997),
            Movie(13, hasFile: true, title: "Firebreak", year: 2025),
            Movie(14, hasFile: true, title: "In the Grey", year: 2025),
            Movie(16, hasFile: true, title: "Animals", year: 2025),
            Movie(15),
            null,
        ];
        _movieFiles =
        [
            MovieFile(12, Bluray1080, "Bluray-1080p", 0, 12.4),
            MovieFile(13, WebRip1080, "WEBRip-1080p", 50, 2),
            MovieFile(14, WebRip1080, "WEBRip-1080p", 150, 3),
            MovieFile(16, WebRip1080, "WEBRip-1080p", 0, 1),
        ];

        await Build();

        var book = Store().Load();
        Assert.Equal(T0, book.ReviewAt);

        // Prima i punteggi più bassi, poi i file più grandi; 150 è l'obiettivo, non sotto.
        Assert.Equal(["movie:12", "movie:16", "movie:13"], book.Review.Select(r => r.Key));
        var amistad = book.Review[0];
        Assert.Equal(
            (DownloadKinds.Movie, "Amistad (1997)", "https://img.example/poster.jpg", 0, (long)(12.4 * Gb), "Bluray-1080p"),
            (amistad.Kind, amistad.Title, amistad.PosterUrl, amistad.Score, amistad.SizeBytes, amistad.Quality));
        Assert.Equal([512, 513, 514, 516], Assert.Single(_arr.MovieFileCalls));
        Assert.Single(_arr.QualityProfileCalls, k => k == ArrKind.Radarr);
    }

    [Fact]
    public async Task AnimeWithoutTargetIsNotListed()
    {
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([new ArrQualityProfile { Id = 4, Name = "Anime HD" }]);
        _movies = [Movie(12, hasFile: true)];
        _movieFiles = [MovieFile(12, WebRip1080, "WEBRip-1080p", 0, 1)];

        await Build();

        var book = Store().Load();
        Assert.Empty(book.Review);
        Assert.Equal(T0, book.ReviewAt);
    }

    [Fact]
    public async Task ASeasonUsesItsWorstEpisode()
    {
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
        [
            new SonarrSeries { Id = 7, Title = "Severance", QualityProfileId = 6, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 5 }, Images = [new ArrImage { CoverType = "poster", RemoteUrl = "https://img.example/sev.jpg" }] },
            new SonarrSeries { Id = 8, Title = "Nothing yet", QualityProfileId = 6, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 0 } },
            null,
        ]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(
        [
            EpisodeFile(2, WebRip1080, "WEBRip-1080p", 30, 2),
            EpisodeFile(2, WebDl1080, "WEBDL-1080p", 10, 3),
            EpisodeFile(2, WebRip1080, "WEBRip-1080p", 40, 2),
            EpisodeFile(1, Bluray1080, "Bluray-1080p", 200, 1),
            EpisodeFile(0, Hdtv720, "HDTV-720p", 0, 1),
            null,
        ]);

        await Build();

        // La stagione 1 è all'obiettivo, gli speciali (stagione 0) non contano.
        var row = Assert.Single(Store().Load().Review);
        Assert.Equal(
            ("season:7:2", DownloadKinds.Season, "Severance · Stagione 2", "https://img.example/sev.jpg", 10, 7 * Gb, "WEBDL-1080p"),
            (row.Key, row.Kind, row.Title, row.PosterUrl, row.Score, row.SizeBytes, row.Quality));
        Assert.Equal([7], _arr.EpisodeFileCalls);
    }

    [Fact]
    public async Task AcceptedTitlesStayOut()
    {
        // 12 "va bene così", 13 è già seguito dal giro.
        var book = new DownloadBook();
        book.Accept("movie:12");
        book.Put(new DownloadEntry { Key = "movie:13", Kind = DownloadKinds.Movie, State = DownloadStates.UpgradeWatch, AvailableSince = T0 });
        Store().Save(book);
        _movies = [Movie(12, hasFile: true), Movie(13, hasFile: true), Movie(14, hasFile: true)];
        _movieFiles = [MovieFile(12, WebRip1080, "WEBRip-1080p", 0, 1), MovieFile(13, WebRip1080, "WEBRip-1080p", 0, 1), MovieFile(14, WebRip1080, "WEBRip-1080p", 0, 1)];

        await Build();

        Assert.Equal(["movie:14"], Store().Load().Review.Select(r => r.Key));
    }

    [Fact]
    public async Task AServiceDownKeepsItsRows()
    {
        var yesterday = T0 - TimeSpan.FromDays(1);
        var book = new DownloadBook();
        book.SetReview(
        [
            new ReviewItem { Key = "movie:20", Kind = DownloadKinds.Movie, Score = 0 },
            new ReviewItem { Key = "season:7:1", Kind = DownloadKinds.Season, Score = 5 },
        ], yesterday);
        Store().Save(book);
        _arr.LibraryMovies = () => Task.FromException<IReadOnlyList<RadarrMovie?>>(new ArrException(ArrError.Unreachable));
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 7, Title = "Severance", QualityProfileId = 6, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 1 } }]);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>([EpisodeFile(2, WebRip1080, "WEBRip-1080p", 30, 2)]);

        await Build();

        // Radarr giù: la sua riga resta; Sonarr risponde: la sua si rifà.
        var saved = Store().Load();
        Assert.Equal(["movie:20", "season:7:2"], saved.Review.Select(r => r.Key));
        Assert.Equal(T0, saved.ReviewAt);

        // Tutti e due giù: niente cambia, nemmeno la data.
        _arr.Series = () => Task.FromException<IReadOnlyList<SonarrSeries?>>(new ArrException(ArrError.Unauthorized));
        _time.Advance(TimeSpan.FromDays(1));
        await Build();
        saved = Store().Load();
        Assert.Equal(["movie:20", "season:7:2"], saved.Review.Select(r => r.Key));
        Assert.Equal(T0, saved.ReviewAt);
    }

    [Fact]
    public async Task ABlockedImportIsImportedByHand()
    {
        AdminGrabBlocked(12, 90, "D1");
        var file = ImportItem("/dl/a.mkv", 12);
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [file, ImportItem("/dl/sample.mkv", 12, "Sample"), ImportItem("/dl/x.nfo", null), null]);

        await _service.RunCycleAsync(CancellationToken.None);

        // Solo il file del film: niente sample, niente file senza film.
        Assert.Equal((ArrKind.Radarr, "D1"), Assert.Single(_arr.ManualImportReadCalls));
        var (kind, items) = Assert.Single(_arr.ManualImportCalls);
        Assert.Equal(ArrKind.Radarr, kind);
        Assert.Same(file, Assert.Single(items));
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (string?)null, false), (entry.State, entry.Reason, entry.ManualImportPending));

        // Una volta sola: se la coda resta bloccata al giro dopo, serve l'admin.
        _time.Advance(DownloadService.CycleInterval);
        await _service.RunCycleAsync(CancellationToken.None);

        entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.ImportBlocked), (entry.State, entry.Reason));
        Assert.Single(_arr.ManualImportCalls);
    }

    [Fact]
    public async Task OnlyTheLargestFileOfTheMovieIsImported()
    {
        // Un extra senza "Sample" nel nome: importato prenderebbe il posto del film (ruling 14).
        AdminGrabBlocked(12, 90, "D1");
        var film = ImportItem("/dl/a.mkv", 12);
        film.Size = 4 * Gb;
        var extra = ImportItem("/dl/featurette.mkv", 12);
        extra.Size = Gb / 3;
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>([extra, film]);

        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Same(film, Assert.Single(Assert.Single(_arr.ManualImportCalls).Items));
    }

    [Fact]
    public async Task AFailedManualImportNeedsYou()
    {
        // 12: Radarr non accetta il comando; 13: nessun file da importare.
        AdminGrabBlocked(12, 90, "D1");
        AdminGrabBlocked(13, 91, "D2");
        _arr.ManualImportItems = (_, id) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(id == "D1" ? [ImportItem("/dl/a.mkv", 12)] : []);
        _arr.ManualImport = (_, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        await _service.RunCycleAsync(CancellationToken.None);

        foreach (var key in new[] { "movie:12", "movie:13" })
        {
            var entry = Saved(key)!;
            Assert.Equal((DownloadStates.NeedsYou, DownloadReasons.ImportBlocked, false), (entry.State, entry.Reason, entry.ManualImportPending));
        }

        Assert.Single(_arr.ManualImportCalls);
    }

    [Fact]
    public async Task ASeasonPackIsImportedOnceForItsDownload()
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "season:7:2", Kind = DownloadKinds.Season, SeriesId = 7, State = DownloadStates.Downloading, AvailableSince = T0, PreviousScore = 0, ManualImportPending = true });
        Store().Save(book);
        _sonarrQueue = [EpisodeQueue(61, 202, 0), EpisodeQueue(60, 201, 0)];
        foreach (var record in _sonarrQueue)
        {
            (record!.DownloadId, record.TrackedDownloadState, record.Status) = ("P", "importBlocked", "completed");
        }

        ArrManualImportItem Episode(int id, string name = "", long size = Gb) => new()
        {
            Path = $"/dl/e{id}{name}.mkv",
            Series = new ArrFileRef { Id = 7 },
            Episodes = [new ArrFileRef { Id = id }],
            Quality = JsonDocument.Parse("{}").RootElement,
            Size = size,
        };

        // Due file per l'episodio 201: si importa il più grande (ruling 14).
        _arr.ManualImportItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [Episode(201, "-extra", Gb / 10), Episode(201), Episode(202), new ArrManualImportItem { Path = "/dl/x.mkv", Series = new ArrFileRef { Id = 7 }, Quality = JsonDocument.Parse("{}").RootElement }]);

        await _service.RunCycleAsync(CancellationToken.None);

        // Un pack ha un elemento di coda per episodio, ma un download solo; un file senza episodi non si importa.
        Assert.Equal((ArrKind.Sonarr, "P"), Assert.Single(_arr.ManualImportReadCalls));
        Assert.Equal(["/dl/e201.mkv", "/dl/e202.mkv"], Assert.Single(_arr.ManualImportCalls).Items.Select(i => i.Path));
    }

    // Amistad (film 12, 155 minuti) su un Bluray-1080p da 0 punti e 12,4 GB: è da ripassare.
    private async Task AmistadToReview()
    {
        _movies = [Movie(12, hasFile: true, title: "Amistad", year: 1997)];
        _movieFiles = [MovieFile(12, Bluray1080, "Bluray-1080p", 0, 12.4)];
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);
        await Build();
    }

    [Fact]
    public async Task HuntTurnsAReviewItemIntoAnUpgradeWatch()
    {
        await AmistadToReview();
        var nudges = 0;
        _service.Nudged += () => nudges++;
        _time.Advance(TimeSpan.FromHours(1));
        var now = _time.GetUtcNow();

        Assert.Equal(HuntOutcome.Ok, _service.Hunt("movie:12"));

        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadKinds.Movie, "Amistad (1997)", "https://img.example/poster.jpg", DownloadStates.UpgradeWatch), (entry.Kind, entry.Title, entry.PosterUrl, entry.State));
        Assert.Equal(((int?)0, (int?)Bluray1080, (long?)(long)(12.4 * Gb)), (entry.CurrentScore, entry.CurrentQualityId, entry.CurrentSizeBytes));
        Assert.Equal((4, 155), (entry.ProfileId, entry.RuntimeMinutes));
        Assert.Equal((now + DownloadSchedule.UpgradeWindow, now), (entry.UpgradeUntil, entry.NextSearchAt));
        Assert.Empty(Store().Load().Review);
        Assert.Equal(1, nudges);

        var overview = await _service.OverviewAsync(CancellationToken.None);
        Assert.Empty(overview.Review);
        Assert.Equal(("movie:12", DownloadSearchPhases.Queued), (Assert.Single(overview.Waiting).Key, overview.Waiting[0].SearchPhase));
    }

    [Fact]
    public async Task AHuntedTitleIsSearchedWithTheUpgradeRule()
    {
        await AmistadToReview();
        _service.Hunt("movie:12");

        // Più punti ma una qualità più bassa del Bluray: Radarr non lo importerebbe.
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([Release("web", WebRip1080, "WEBRip-1080p", 5, 150)]);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal((ArrKind.Radarr, "movieId=12"), Assert.Single(_arr.SearchReleaseCalls));
        Assert.Empty(_arr.GrabCalls);
        Assert.Equal(DownloadStates.UpgradeWatch, Saved("movie:12")!.State);

        // Più punti e la stessa qualità: si scarica come upgrade del file di prima.
        Assert.Equal(HuntOutcome.Ok, _service.Hunt("movie:12"));
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([Release("bd", Bluray1080, "Bluray-1080p", 14, 150)]);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal("bd", Assert.Single(_arr.GrabCalls).Guid);
        var entry = Saved("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, (int?)0, (int?)Bluray1080, (int?)150), (entry.State, entry.PreviousScore, entry.PreviousQualityId, entry.CurrentScore));

        // Importato: il file nuovo è all'obiettivo e la voce esce.
        _movieFiles = [MovieFile(12, Bluray1080, "Bluray-1080p", 150, 14)];
        _time.Advance(DownloadService.CycleInterval);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Equal([512], _arr.MovieFileCalls[^1]);
        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task HuntOnASeasonUsesItsEpisodes()
    {
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
            [new SonarrSeries { Id = 7, Title = "Severance", QualityProfileId = 6, Runtime = 50, Monitored = true, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 3 } }]);
        var files = new List<ArrFile?> { EpisodeFile(2, WebRip1080, "WEBRip-1080p", 30, 2), EpisodeFile(2, WebDl1080, "WEBDL-1080p", 10, 3), EpisodeFile(1, Bluray1080, "Bluray-1080p", 10, 1) };
        (files[0]!.Id, files[1]!.Id, files[2]!.Id) = (71, 72, 70);
        _arr.EpisodeFiles = _ => Task.FromResult<IReadOnlyList<ArrFile?>>(files);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
        [
            new SonarrEpisode { Id = 205, SeriesId = 7, SeasonNumber = 2, EpisodeNumber = 5, EpisodeFileId = 72 },
            new SonarrEpisode { Id = 203, SeriesId = 7, SeasonNumber = 2, EpisodeNumber = 3, EpisodeFileId = 71 },
            new SonarrEpisode { Id = 206, SeriesId = 7, SeasonNumber = 2, EpisodeNumber = 6 },
            new SonarrEpisode { Id = 101, SeriesId = 7, SeasonNumber = 1, EpisodeNumber = 1, EpisodeFileId = 70 },
        ]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 1, Priority = 25 }]);
        await Build();

        Assert.Equal(HuntOutcome.Ok, _service.Hunt("season:7:2"));

        // Gli episodi dei file della stagione, il peggiore come file di adesso.
        var entry = Saved("season:7:2")!;
        Assert.Equal([3, 5], entry.EpisodeNumbers!);
        Assert.Equal((7, 6, 50, (int?)10, (int?)WebDl1080, (long?)(5 * Gb)), (entry.SeriesId, entry.ProfileId, entry.RuntimeMinutes, entry.CurrentScore, entry.CurrentQualityId, entry.CurrentSizeBytes));

        await _service.RunCycleAsync(CancellationToken.None);
        Assert.Contains((ArrKind.Sonarr, "seriesId=7&seasonNumber=2"), _arr.SearchReleaseCalls);
    }

    [Fact]
    public void HuntOnAnExistingEntryIsSearchNow()
    {
        var later = T0 + TimeSpan.FromHours(6);
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "movie:12", Kind = DownloadKinds.Movie, State = DownloadStates.Waiting, AvailableSince = T0, NextSearchAt = later });
        book.Put(new DownloadEntry { Key = "movie:13", Kind = DownloadKinds.Movie, State = DownloadStates.NeedsYou, Reason = DownloadReasons.ImportBlocked, AvailableSince = T0, NextSearchAt = later });
        book.Put(new DownloadEntry { Key = "movie:14", Kind = DownloadKinds.Movie, State = DownloadStates.Downloading, AvailableSince = T0, NextSearchAt = later });
        Store().Save(book);
        var nudges = 0;
        _service.Nudged += () => nudges++;

        Assert.Equal(HuntOutcome.Ok, _service.Hunt("movie:12"));
        Assert.Equal((T0, 1), (Saved("movie:12")!.NextSearchAt, nudges));

        // Un import bloccato o un download in corso non si cercano.
        Assert.Equal(HuntOutcome.Changed, _service.Hunt("movie:13"));
        Assert.Equal(HuntOutcome.Changed, _service.Hunt("movie:14"));
        Assert.Equal(later, Saved("movie:13")!.NextSearchAt);
        Assert.Equal(1, nudges);
    }

    [Fact]
    public void HuntWithoutReviewOrEntryIsChanged()
    {
        Assert.Equal(HuntOutcome.Invalid, _service.Hunt("nope"));
        Assert.Equal(HuntOutcome.Changed, _service.Hunt("movie:12"));
        Assert.Null(SavedBook()?.Get("movie:12"));
    }

    [Fact]
    public void HuntOnAnOldReviewItemWithoutQualityIsChanged()
    {
        // Salvati da una versione senza QualityId (né episodi): il prossimo elenco li rifà.
        var book = new DownloadBook();
        book.SetReview(
        [
            new ReviewItem { Key = "movie:12", Kind = DownloadKinds.Movie, Score = 0, ProfileId = 4 },
            new ReviewItem { Key = "season:7:2", Kind = DownloadKinds.Season, Score = 0, ProfileId = 6, QualityId = WebDl1080 },
        ], T0);
        Store().Save(book);

        Assert.Equal(HuntOutcome.Changed, _service.Hunt("movie:12"));
        Assert.Equal(HuntOutcome.Changed, _service.Hunt("season:7:2"));
        Assert.Equal(2, Store().Load().Review.Count);
        Assert.Empty(Store().Load().Entries);
    }

    [Fact]
    public async Task HuntOnAnUnmonitoredMovieIsChanged()
    {
        await AmistadToReview();
        _movies = [Movie(12, monitored: false, hasFile: true, title: "Amistad", year: 1997)];
        await Build();

        // Il giro toglierebbe la voce prima di cercarla: niente pulsante e niente voce.
        Assert.False(Assert.Single((await _service.OverviewAsync(CancellationToken.None)).Review).CanHunt);
        Assert.Equal(HuntOutcome.Changed, _service.Hunt("movie:12"));
        Assert.Null(Saved("movie:12"));
    }

    [Fact]
    public async Task CanHuntNeedsMonitoringQualityAndEpisodes()
    {
        var book = new DownloadBook();
        book.SetReview(
        [
            new ReviewItem { Key = "movie:1", Kind = DownloadKinds.Movie, Monitored = true, QualityId = Bluray1080 },
            new ReviewItem { Key = "movie:2", Kind = DownloadKinds.Movie, Monitored = true },
            new ReviewItem { Key = "movie:3", Kind = DownloadKinds.Movie, QualityId = Bluray1080 },
            new ReviewItem { Key = "season:7:1", Kind = DownloadKinds.Season, Monitored = true, QualityId = WebDl1080, EpisodeNumbers = [1, 2] },
            new ReviewItem { Key = "season:7:2", Kind = DownloadKinds.Season, Monitored = true, QualityId = WebDl1080, EpisodeNumbers = [] },
            new ReviewItem { Key = "season:7:3", Kind = DownloadKinds.Season, Monitored = true, QualityId = WebDl1080 },
        ], T0);
        Store().Save(book);

        var review = (await _service.OverviewAsync(CancellationToken.None)).Review;

        Assert.Equal([true, false, false, true, false, false], review.Select(r => r.CanHunt));
    }

    [Fact]
    public async Task ASeriesWithoutEpisodesKeepsTheOtherSeasons()
    {
        _arr.Series = () => Task.FromResult<IReadOnlyList<SonarrSeries?>>(
        [
            new SonarrSeries { Id = 7, Title = "Severance", QualityProfileId = 6, Monitored = true, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 1 } },
            new SonarrSeries
            {
                Id = 8, Title = "Andor", QualityProfileId = 6, Monitored = true, Statistics = new SonarrSeriesStatistics { EpisodeFileCount = 2 },
                Seasons = [new SonarrSeason { SeasonNumber = 1, Monitored = true }, new SonarrSeason { SeasonNumber = 2, Monitored = false }, null],
            },
        ]);
        _arr.EpisodeFiles = id =>
        {
            var first = EpisodeFile(1, WebRip1080, "WEBRip-1080p", 30, 2);
            var second = EpisodeFile(2, WebRip1080, "WEBRip-1080p", 30, 2);
            (first.Id, second.Id) = (id * 10, (id * 10) + 1);
            return Task.FromResult<IReadOnlyList<ArrFile?>>(id == 7 ? [first] : [first, second]);
        };
        _arr.SeriesEpisodes = id => id == 7
            ? Task.FromException<IReadOnlyList<SonarrEpisode?>>(new ArrException(ArrError.Unreachable))
            : Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
                [new SonarrEpisode { Id = 801, SeasonNumber = 1, EpisodeNumber = 1, EpisodeFileId = 80 }, new SonarrEpisode { Id = 802, SeasonNumber = 2, EpisodeNumber = 1, EpisodeFileId = 81 }]);

        await Build();

        // Severance senza episodi resta una riga, senza pulsante; Andor si rifà, la stagione 2 non monitorata senza pulsante.
        var saved = Store().Load();
        Assert.Equal(T0, saved.ReviewAt);
        Assert.Equal(["season:7:1", "season:8:1", "season:8:2"], saved.Review.Select(r => r.Key).Order());
        Assert.Null(saved.Review.Single(r => r.Key == "season:7:1").EpisodeNumbers);
        Assert.Equal([1], saved.Review.Single(r => r.Key == "season:8:1").EpisodeNumbers!);
        var review = (await _service.OverviewAsync(CancellationToken.None)).Review.ToDictionary(r => r.Key, r => r.CanHunt);
        Assert.Equal((false, true, false), (review["season:7:1"], review["season:8:1"], review["season:8:2"]));
    }
}
