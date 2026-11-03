using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;
using static Jellyfin.Plugin.WonderFlixWatchParty.Tests.DownloadTestData;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Un torrent già in qBittorrent: trovarlo dopo un rifiuto di Radarr/Sonarr e importarne i file.</summary>
public sealed class DownloadServiceExistingTorrentTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 3, 12, 0, 0, TimeSpan.Zero);
    private static readonly long Now = T0.ToUnixTimeSeconds();

    private const string DuplicateOf = "Detected an attempt to add a duplicate torrent. Existing torrent: {0}. Result: Trackers cannot be merged because it is a private torrent";

    private readonly TempFolder _folder = new();
    private readonly FakeArrClient _arr = new();
    private readonly FakeQbitClient _qbit = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly DownloadService _service;

    public DownloadServiceExistingTorrentTests()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([Movie(12, title: "Animals", year: 2025, runtime: 106)]);
        _arr.Queue = _ => Task.FromResult<IReadOnlyList<ArrQueueItem?>>([]);
        _arr.Releases = (_, _) => Task.FromResult<IReadOnlyList<ArrRelease?>>([Release("b", WebRip1080, "WEBRip-1080p", 1.89, 150, indexerId: 3)]);
        _arr.QualityProfiles = _ => Task.FromResult<IReadOnlyList<ArrQualityProfile?>>([MainProfile(4)]);
        _arr.Indexers = _ => Task.FromResult<IReadOnlyList<ArrIndexer?>>([new ArrIndexer { Id = 3, Priority = 10 }]);
        _service = Service(_qbit);
    }

    public void Dispose() => _folder.Dispose();

    private DownloadService Service(IQbitClient? qbit) =>
        new(_arr, new FakeArrSettings(), new FakeDownloadSettings(), Store(), _time, NullLogger<DownloadService>.Instance, null, qbit) { Pause = TimeSpan.Zero };

    private DownloadStore Store() => new(_folder.DownloadsFile, NullLogger<DownloadStore>.Instance);

    private static QbitLogEntry Line(string name, long timestamp, long id = 1) =>
        new() { Id = id, Message = string.Format(null, DuplicateOf, name), Timestamp = timestamp };

    private static QbitTorrent Torrent(string name, double progress = 1, string hash = "ABC123", string? contentPath = "/dl/Pack") =>
        new() { Hash = hash, Name = name, Progress = progress, ContentPath = contentPath };

    // La release "b" di Animals è rifiutata dal client di download.
    private async Task<ExistingTorrent?> RefusedGrab()
    {
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));
        var (outcome, existing) = await _service.GrabOrFindExistingAsync("movie:12", "b", 3, CancellationToken.None);
        Assert.Equal(GrabOutcome.Refused, outcome);
        return existing;
    }

    [Fact]
    public async Task ARefusalWithADuplicateLineFindsTheTorrent()
    {
        // Due righe: conta la più recente tra quelle scritte dopo l'inizio (2 s di margine per la precisione del secondo).
        _qbit.Log.AddRange([Line("Vecchio", Now - 100, 1), Line("Pack", Now - 2, 2), Line("Altro", Now + 1, 3), Line("Altro", Now + 5, 4)]);
        _qbit.Log.Add(new QbitLogEntry { Id = 5, Message = "Un altro messaggio", Timestamp = Now + 9 });
        _qbit.Torrents.AddRange([Torrent("Altro", hash: "OTHER", contentPath: "/dl/Altro"), Torrent("Pack"), Torrent("Vecchio")]);

        var existing = await RefusedGrab();

        Assert.Equal(new ExistingTorrent("OTHER", "Altro"), existing);
        Assert.Equal(1, _qbit.LogReads);
    }

    [Fact]
    public async Task ARefusalWithTheLineOfThisGrabFindsItsTorrent()
    {
        _qbit.Log.AddRange([Line("Vecchio", Now - 3, 1), Line("Pack", Now - 2, 2)]);
        _qbit.Torrents.AddRange([Torrent("Pack"), Torrent("Vecchio", hash: "OLD")]);

        Assert.Equal(new ExistingTorrent("ABC123", "Pack"), await RefusedGrab());
    }

    [Fact]
    public async Task ARefusalWithoutALogLineHasNoTorrent()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Assert.Null(await RefusedGrab());

        _qbit.Log.Add(new QbitLogEntry { Id = 1, Message = "Torrent aggiunto", Timestamp = Now });
        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task AnOlderLineIsNotThisRefusal()
    {
        _qbit.Log.Add(Line("Pack", Now - 3));
        _qbit.Torrents.Add(Torrent("Pack"));

        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task AnUnfinishedTorrentIsNotOffered()
    {
        _qbit.Log.Add(Line("Pack", Now));
        _qbit.Torrents.Add(Torrent("Pack", progress: 0.99));

        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task TwoTorrentsWithTheSameNameAreNotOffered()
    {
        _qbit.Log.Add(Line("Pack", Now));
        _qbit.Torrents.AddRange([Torrent("Pack"), Torrent("Pack", hash: "DEF456")]);

        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task ATorrentWithoutContentPathIsNotOffered()
    {
        _qbit.Log.Add(Line("Pack", Now));
        _qbit.Torrents.Add(Torrent("Pack", contentPath: ""));

        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task AFailingQbittorrentLeavesTheRefusal()
    {
        _qbit.Fail = QbitError.Unreachable;
        Assert.Null(await RefusedGrab());
    }

    [Fact]
    public async Task WithoutQbittorrentTheRefusalIsAsToday()
    {
        var service = Service(null);
        _arr.Grab = (_, _, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));

        Assert.Equal((GrabOutcome.Refused, (ExistingTorrent?)null), await service.GrabOrFindExistingAsync("movie:12", "b", 3, CancellationToken.None));
    }

    [Fact]
    public async Task AGrabThatWorksDoesNotReadTheLog()
    {
        _qbit.Log.Add(Line("Pack", Now));
        _qbit.Torrents.Add(Torrent("Pack"));

        Assert.Equal((GrabOutcome.Ok, (ExistingTorrent?)null), await _service.GrabOrFindExistingAsync("movie:12", "b", 3, CancellationToken.None));
        Assert.Equal(0, _qbit.LogReads);
    }

    // ---- ImportExistingAsync ----

    private static ArrManualImportItem PackFile(int series, int season, int episode, long size = Gb) => new()
    {
        Path = $"/dl/Pack/S{season}E{episode}.mkv",
        Series = new ArrFileRef { Id = series },
        Episodes = [new ArrFileRef { Id = episode }],
        SeasonNumber = season,
        Quality = JsonDocument.Parse("{}").RootElement,
        Size = size,
    };

    private void Pack(params ArrManualImportItem[] files) =>
        _arr.ManualImportFolderItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(files);

    // Voci già nel libro, tutte da cercare subito: se il giro le ritrova in attesa le cerca e le scarica.
    private void Preexisting(params (string Key, string Kind, string State)[] entries) =>
        Save([.. entries.Select(e => new DownloadEntry { Key = e.Key, Kind = e.Kind, Title = e.Key, State = e.State, AvailableSince = T0, NextSearchAt = T0 })]);

    private void Save(params DownloadEntry[] entries)
    {
        var book = new DownloadBook();
        foreach (var entry in entries)
        {
            book.Put(entry);
        }

        Store().Save(book);
    }

    [Fact]
    public async Task ASeasonIsImportedFromAMultiSeasonPackWithACopy()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 2, 201), PackFile(7, 3, 301), PackFile(7, 3, 302), PackFile(8, 3, 801));
        Preexisting(
            ("season:7:3", DownloadKinds.Season, DownloadStates.Downloading),
            ("episode:301", DownloadKinds.Episode, DownloadStates.NeedsYou),
            ("episode:302", DownloadKinds.Episode, DownloadStates.Waiting),
            ("episode:201", DownloadKinds.Episode, DownloadStates.Waiting));
        var nudges = 0;
        _service.Nudged += () => nudges++;

        // L'hash si legge senza distinguere le maiuscole.
        Assert.Equal((BlockedOutcome.Ok, (string?)null), await _service.ImportExistingAsync("season:7:3", "abc123".ToLowerInvariant()));

        Assert.Equal([(ArrKind.Sonarr, "/dl/Pack")], _arr.ManualImportFolderReadCalls);
        var (kind, items) = Assert.Single(_arr.ManualImportCalls);
        Assert.Equal(ArrKind.Sonarr, kind);
        Assert.Equal(["/dl/Pack/S3E301.mkv", "/dl/Pack/S3E302.mkv"], items.Select(i => i.Path));
        Assert.Equal([true], _arr.ManualImportCopies);

        // Gli episodi dei file escono dal libro; la stagione resta in download finché non arriva il file. Sono tutti accettati;
        // l'episodio di un'altra stagione resta.
        var saved = Store().Load();
        foreach (var gone in new[] { "episode:301", "episode:302" })
        {
            Assert.Null(saved.Get(gone));
        }

        foreach (var accepted in new[] { "season:7:3", "episode:301", "episode:302" })
        {
            Assert.True(saved.IsAccepted(accepted), accepted);
        }

        Assert.Equal(DownloadStates.Downloading, saved.Get("season:7:3")!.State);
        Assert.NotNull(saved.Get("episode:201"));
        Assert.False(saved.IsAccepted("episode:201"));
        Assert.Empty(saved.Lightened);
        Assert.Equal(1, nudges);
    }

    [Fact]
    public async Task ASeasonImportKeepsTheEpisodesThatDownloadAndDropsTheOthers()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 3, 301), PackFile(7, 3, 302), PackFile(7, 3, 303));
        Preexisting(
            ("season:7:3", DownloadKinds.Season, DownloadStates.NeedsYou),
            ("episode:301", DownloadKinds.Episode, DownloadStates.Downloading),
            ("episode:302", DownloadKinds.Episode, DownloadStates.Waiting),
            ("episode:303", DownloadKinds.Episode, DownloadStates.UpgradeWatch));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("season:7:3", "ABC123")).Outcome);

        var saved = Store().Load();
        Assert.Equal(DownloadStates.Downloading, saved.Get("episode:301")!.State);
        Assert.Null(saved.Get("episode:302"));
        Assert.Null(saved.Get("episode:303"));
        Assert.Equal(DownloadStates.Downloading, saved.Get("season:7:3")!.State);
        Assert.All(new[] { "season:7:3", "episode:301", "episode:302", "episode:303" }, k => Assert.True(saved.IsAccepted(k), k));
    }

    [Fact]
    public async Task AnImportedSeasonWithStaleEpisodeNumbersIsNotDownloadedAgain()
    {
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        var aired = T0 - TimeSpan.FromDays(30);
        var episodes = new[] { 201, 202, 203 }.Select((id, i) => { var e = Episode(id, aired); e.EpisodeNumber = i + 1; return e; }).ToList();
        var done = Episode(204, aired);
        done.EpisodeNumber = 4;

        // Non intera (il quarto ha il file): senza numeri la voce di stagione prende tutti i mancanti.
        _arr.MissingEpisodes = () => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([.. episodes]);
        _arr.SeriesEpisodes = _ => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([.. episodes, done]);
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 2, 201), PackFile(7, 2, 202), PackFile(7, 2, 203));
        Save(new DownloadEntry
        {
            Key = "season:7:2",
            Kind = DownloadKinds.Season,
            Title = "Severance · Stagione 2",
            State = DownloadStates.NeedsYou,
            AvailableSince = T0,
            NextSearchAt = T0,
            SeriesId = 7,
            EpisodeNumbers = [1, 2],
        });

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("season:7:2", "ABC123")).Outcome);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(_arr.GrabCalls);
        var saved = Store().Load();
        Assert.Equal(DownloadStates.Downloading, saved.Get("season:7:2")!.State);
        Assert.Null(saved.Get("episode:203"));
    }

    [Fact]
    public async Task ALightenImportMarksOnlyTheKeyItself()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        MovieFile();
        Preexisting(("movie:12", DownloadKinds.Movie, DownloadStates.NeedsYou));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123", lighten: true)).Outcome);

        Assert.Equal(T0, Assert.Single(_service.LightenedKeys()).Value);
        Assert.True(_service.LightenedKeys().ContainsKey("movie:12"));
    }

    [Fact]
    public async Task AnImportWithoutLightenMarksNothing()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        MovieFile();
        Preexisting(("movie:12", DownloadKinds.Movie, DownloadStates.NeedsYou));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123")).Outcome);

        Assert.Empty(_service.LightenedKeys());
    }

    [Fact]
    public async Task AnImportedTitleWithoutItsFileYetIsNotDownloadedAgain()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        MovieFile();
        Preexisting(("movie:12", DownloadKinds.Movie, DownloadStates.NeedsYou));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123")).Outcome);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Empty(_arr.SearchReleaseCalls);
        Assert.Empty(_arr.GrabCalls);
        Assert.Equal(DownloadStates.Downloading, Store().Load().Get("movie:12")!.State);
    }

    [Fact]
    public async Task AnImportedTitleWithItsFileLeavesTheBookAndSkipsTheUpgradeWatch()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        MovieFile();

        // Un tappabuchi con una scelta di prima: senza l'import, col file andrebbe in UpgradeWatch.
        Save(new DownloadEntry
        {
            Key = "movie:12",
            Kind = DownloadKinds.Movie,
            Title = "Animals (2025)",
            State = DownloadStates.NeedsYou,
            AvailableSince = T0,
            NextSearchAt = T0,
            Stopgap = DownloadStopgaps.Score,
            CurrentScore = 10,
            CurrentSizeBytes = Gb,
            PreviousScore = 5,
            ManualImportPending = true,
        });
        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123")).Outcome);

        var held = Store().Load().Get("movie:12")!;
        Assert.Equal(DownloadStates.Downloading, held.State);
        Assert.Null(held.Stopgap);
        Assert.Null(held.CurrentScore);
        Assert.Null(held.PreviousScore);
        Assert.False(held.ManualImportPending);

        // Il file è arrivato.
        _arr.LibraryMovies = () => Task.FromResult<IReadOnlyList<RadarrMovie?>>([Movie(12, title: "Animals", year: 2025, runtime: 106, hasFile: true)]);
        await _service.RunCycleAsync(CancellationToken.None);

        Assert.Null(Store().Load().Get("movie:12"));
        Assert.Empty(_arr.GrabCalls);
    }

    [Fact]
    public async Task AnImportWithoutAnEntryCreatesItFromTheRememberedSearch()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        MovieFile();
        await _service.SearchAsync("movie:12", CancellationToken.None);
        Assert.Null(Store().Load().Get("movie:12"));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123")).Outcome);

        var created = Store().Load().Get("movie:12")!;
        Assert.Equal((DownloadStates.Downloading, "Animals (2025)", T0), (created.State, created.Title, created.LastSearchAt));
    }

    private void MovieFile() =>
        _arr.ManualImportFolderItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
            [new ArrManualImportItem { Path = "/dl/Film/a.mkv", Movie = new ArrFileRef { Id = 12 }, Quality = JsonDocument.Parse("{}").RootElement, Size = 5 * Gb }]);

    [Fact]
    public async Task AnEpisodeIsImportedAloneFromAPack()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 3, 301), PackFile(7, 3, 302));
        Preexisting(("episode:301", DownloadKinds.Episode, DownloadStates.NeedsYou), ("episode:302", DownloadKinds.Episode, DownloadStates.NeedsYou));

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);

        Assert.Equal(["/dl/Pack/S3E301.mkv"], Assert.Single(_arr.ManualImportCalls).Items.Select(i => i.Path));
        // La voce dell'episodio resta in download finché non arriva il file; l'altro episodio non si tocca.
        var saved = Store().Load();
        Assert.Equal(DownloadStates.Downloading, saved.Get("episode:301")!.State);
        Assert.True(saved.IsAccepted("episode:301"));
        Assert.Equal(DownloadStates.NeedsYou, saved.Get("episode:302")!.State);
    }

    [Fact]
    public async Task AMovieIsImportedFromItsTorrent()
    {
        _qbit.Torrents.Add(Torrent("Film", contentPath: "/dl/Film"));
        _arr.ManualImportFolderItems = (_, _) => Task.FromResult<IReadOnlyList<ArrManualImportItem?>>(
        [
            new ArrManualImportItem { Path = "/dl/Film/a.mkv", Movie = new ArrFileRef { Id = 12 }, Quality = JsonDocument.Parse("{}").RootElement, Size = 5 * Gb },
            new ArrManualImportItem { Path = "/dl/Film/b.mkv", Movie = new ArrFileRef { Id = 99 }, Quality = JsonDocument.Parse("{}").RootElement, Size = 9 * Gb },
        ]);

        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("movie:12", "ABC123")).Outcome);

        Assert.Equal((ArrKind.Radarr, "/dl/Film"), Assert.Single(_arr.ManualImportFolderReadCalls));
        Assert.Equal(["/dl/Film/a.mkv"], Assert.Single(_arr.ManualImportCalls).Items.Select(i => i.Path));
        Assert.True(Store().Load().IsAccepted("movie:12"));
    }

    [Fact]
    public async Task FilesOfAnotherTitleAreNoFilesAndNoCommand()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 2, 201), PackFile(8, 3, 801));
        Preexisting(("season:7:3", DownloadKinds.Season, DownloadStates.Downloading));

        Assert.Equal((BlockedOutcome.Failed, (string?)"NoFiles"), await _service.ImportExistingAsync("season:7:3", "ABC123"));

        Assert.Empty(_arr.ManualImportCalls);
        Assert.NotNull(Store().Load().Get("season:7:3"));
    }

    [Fact]
    public async Task AnArrErrorFailsTheImportAndKeepsTheEntry()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        Pack(PackFile(7, 3, 301));
        _arr.ManualImport = (_, _) => Task.FromException(new ArrException(ArrError.Unreachable, status: 500));
        Preexisting(("episode:301", DownloadKinds.Episode, DownloadStates.NeedsYou));

        Assert.Equal((BlockedOutcome.Failed, (string?)"Unreachable"), await _service.ImportExistingAsync("episode:301", "ABC123"));

        var saved = Store().Load();
        Assert.NotNull(saved.Get("episode:301"));
        Assert.False(saved.IsAccepted("episode:301"));
    }

    [Fact]
    public async Task ABusyKeyIsChanged()
    {
        _qbit.Torrents.Add(Torrent("Pack"));
        var reading = new TaskCompletionSource();
        var gate = new TaskCompletionSource<IReadOnlyList<ArrManualImportItem?>>();
        _arr.ManualImportFolderItems = (_, _) =>
        {
            reading.TrySetResult();
            return gate.Task;
        };

        var first = _service.ImportExistingAsync("episode:301", "ABC123");
        await reading.Task;
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);

        gate.SetResult([PackFile(7, 3, 301)]);
        Assert.Equal(BlockedOutcome.Ok, (await first).Outcome);

        // La chiave è libera di nuovo.
        Assert.Equal(BlockedOutcome.Ok, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);
    }

    [Fact]
    public async Task ATorrentThatIsGoneUnfinishedOrWithoutAPathIsChanged()
    {
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);

        _qbit.Torrents.Add(Torrent("Pack", progress: 0.5));
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);

        _qbit.Torrents.Clear();
        _qbit.Torrents.Add(Torrent("Pack", contentPath: null));
        Assert.Equal(BlockedOutcome.Changed, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);

        Assert.Empty(_arr.ManualImportFolderReadCalls);
    }

    [Fact]
    public async Task WithoutQbittorrentOrWhenItFailsTheImportIsUnavailable()
    {
        Assert.Equal(BlockedOutcome.Unavailable, (await Service(null).ImportExistingAsync("episode:301", "ABC123")).Outcome);

        _qbit.Fail = QbitError.Unreachable;
        Assert.Equal(BlockedOutcome.Unavailable, (await _service.ImportExistingAsync("episode:301", "ABC123")).Outcome);
    }

    [Theory]
    [InlineData("nope", "ABC123")]
    [InlineData("episode:301", "")]
    [InlineData("episode:301", "  ")]
    public async Task AnInvalidKeyOrAnEmptyHashIsInvalid(string key, string hash) =>
        Assert.Equal(BlockedOutcome.Invalid, (await _service.ImportExistingAsync(key, hash)).Outcome);
}
