using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NewTitlesCollectorTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 4, 20, 0, 0, TimeSpan.Zero));
    private readonly RecordingLogger<NewTitlesCollector> _log = new();
    private readonly InboxService _inbox;
    private readonly NewTitlesCollector _collector;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly Guid _bear = Guid.NewGuid();

    public NewTitlesCollectorTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _collector = TestNewTitles.Create(_server, _inbox, _time, _log);
        _collector.Start();
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
    }

    public void Dispose()
    {
        _collector.Dispose();
        _folder.Dispose();
    }

    private Guid AddMovie(string name, int? year = 2024, string[]? keys = null, bool refreshed = true)
    {
        var id = Guid.NewGuid();
        _server.Titles[id] = new LibraryTitle(
            id, true, name, year, Guid.Empty, string.Empty, string.Empty, null, null, keys ?? [], refreshed);
        return id;
    }

    private Guid AddEpisode(Guid seriesId, int? season, int? episode, string seriesName = "The Bear")
    {
        var id = Guid.NewGuid();
        _server.Titles[id] = new LibraryTitle(
            id, false, $"Episodio {episode}", null, seriesId, seriesName, "chiave-" + seriesId.ToString("N"),
            season, episode, [], true);
        return id;
    }

    private InboxEntry? NewTitlesOf(UserRef user) =>
        _inbox.Get(user.Id).Entries.SingleOrDefault(e => e.Type == InboxEntryTypes.NewTitles);

    // Un controllo alla volta, come il timer vero: Advance di un tempo lungo
    // farebbe tutti i controlli del periodo all'ora finale.
    private void Wait(TimeSpan span)
    {
        for (var waited = TimeSpan.Zero; waited < span; waited += NewTitlesCollector.CheckInterval)
        {
            _time.Advance(NewTitlesCollector.CheckInterval);
        }
    }

    [Fact]
    public void AWaveClosesAfterFifteenQuietMinutes()
    {
        _collector.Added(AddMovie("Dune"));
        _time.Advance(TimeSpan.FromMinutes(14));
        var alien = AddMovie("Alien", 1979);
        _collector.Added(alien);
        _time.Advance(TimeSpan.FromMinutes(14));
        Assert.Null(NewTitlesOf(_mario));

        _time.Advance(TimeSpan.FromMinutes(1));

        var entry = NewTitlesOf(_mario);
        Assert.NotNull(entry);
        Assert.Equal(new[] { "Alien", "Dune" }, entry.Movies!.Select(m => m.Name));
        Assert.Equal(alien.ToString("N"), entry.Movies![0].ItemId);
        Assert.Equal(1979, entry.Movies[0].Year);
        Assert.Empty(entry.Series!);
        Assert.Null(entry.More);
        Assert.NotNull(NewTitlesOf(_luigi));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void ALongWaveClosesAfterTwoHours()
    {
        for (var i = 0; i < 13; i++)
        {
            _collector.Added(AddMovie($"Film {i:00}"));
            _time.Advance(TimeSpan.FromMinutes(10));
        }

        // Un titolo ogni 10 minuti: alla seconda ora l'ondata si chiude anche
        // senza quiete; l'ultimo apre l'ondata dopo.
        Assert.Equal(12, NewTitlesOf(_mario)!.Movies!.Count);
        Assert.Equal(1, _collector.Pending);
    }

    [Fact]
    public void AScanInProgressOrMissingMetadataPostponeTheClose()
    {
        _collector.Added(AddMovie("Dune"));
        _server.ScanRunning = true;
        _time.Advance(TimeSpan.FromMinutes(20));
        Assert.Null(NewTitlesOf(_mario));

        _server.ScanRunning = false;
        var raw = AddMovie("dune.part.two.2024.mkv", refreshed: false);
        _collector.Added(raw);
        _time.Advance(TimeSpan.FromMinutes(16));
        Assert.Null(NewTitlesOf(_mario));

        // Arrivano i metadati: nome vero.
        _server.Titles[raw] = _server.Titles[raw] with { Name = "Dune: Parte Due", Refreshed = true };
        _time.Advance(TimeSpan.FromMinutes(1));

        Assert.Equal(new[] { "Dune", "Dune: Parte Due" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void TwoHoursCloseTheWaveEvenDuringAScan()
    {
        _server.ScanRunning = true;
        _collector.Added(AddMovie("Dune", refreshed: false));

        _time.Advance(NewTitlesCollector.MaxWait);

        Assert.NotNull(NewTitlesOf(_mario));
    }

    [Fact]
    public void ReplacementsAndShortLivedTitlesAreNotAnnounced()
    {
        // Radarr: il file vecchio tolto, quello nuovo aggiunto con lo stesso id TMDB.
        _collector.Removed(Guid.NewGuid(), isMovie: true, ["Tmdb:438631"]);
        _collector.Added(AddMovie("Dune", keys: ["Tmdb:438631", "Imdb:tt1160419"]));
        // Aggiunto e tolto nella stessa ondata.
        var gone = AddMovie("Temporaneo");
        _collector.Added(gone);
        _collector.Removed(gone, isMovie: true, []);
        // Cancellato prima della chiusura.
        var deleted = AddMovie("Cancellato");
        _collector.Added(deleted);
        _server.Titles.Remove(deleted);
        _collector.Added(AddMovie("Alien"));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Equal(new[] { "Alien" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void AReplacementNeedsTheSameKind()
    {
        _collector.Removed(Guid.NewGuid(), isMovie: false, ["Tvdb:42"]);
        _collector.Added(AddMovie("Film con lo stesso id", keys: ["Tvdb:42"]));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Single(NewTitlesOf(_mario)!.Movies!);
    }

    [Fact]
    public void EpisodesGoToFollowersMoviesToWhoCanSeeThem()
    {
        var second = AddEpisode(_bear, 3, 2);
        var first = AddEpisode(_bear, 3, 1);
        var film = AddMovie("Dune");
        _server.Following.Add((_mario.Id, _bear));
        _server.Unseen.Add((_luigi.Id, film));
        _collector.Added(second);
        _collector.Added(first);
        _collector.Added(film);

        _time.Advance(NewTitlesCollector.QuietTime);

        var mario = NewTitlesOf(_mario)!;
        var series = Assert.Single(mario.Series!);
        Assert.Equal(_bear.ToString("N"), series.SeriesId);
        Assert.Equal("The Bear", series.Name);
        Assert.Equal(new[] { (3, 1), (3, 2) }, series.Episodes.Select(e => (e.Season!.Value, e.Episode!.Value)));
        Assert.Single(mario.Movies!);
        // Luigi non segue la serie e non vede il film.
        Assert.Null(NewTitlesOf(_luigi));
    }

    [Fact]
    public void EpisodesTheUserCannotSeeAndEpisodesWithoutASeriesAreLeftOut()
    {
        var visible = AddEpisode(_bear, 1, 1);
        var hidden = AddEpisode(_bear, 1, 2);
        var orphan = AddEpisode(Guid.Empty, 1, 1, seriesName: "Senza serie");
        _server.Following.Add((_mario.Id, _bear));
        _server.Following.Add((_mario.Id, Guid.Empty));
        _server.Unseen.Add((_mario.Id, hidden));
        foreach (var id in new[] { visible, hidden, orphan })
        {
            _collector.Added(id);
        }

        _time.Advance(NewTitlesCollector.QuietTime);

        var series = Assert.Single(NewTitlesOf(_mario)!.Series!);
        Assert.Equal(new int?[] { 1 }, series.Episodes.Select(e => e.Episode));
    }

    [Fact]
    public void DisabledUsersGetNothing()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        _collector.Added(AddMovie("Dune"));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Empty(_inbox.Get(bowser.Id).Entries);
        Assert.NotNull(NewTitlesOf(_mario));
    }

    [Fact]
    public void BeyondTheLimitTheRestIsCounted()
    {
        for (var i = 0; i < NewTitlesCollector.MaxLines + 3; i++)
        {
            _collector.Added(AddMovie($"Film {i:000}"));
        }

        _time.Advance(NewTitlesCollector.QuietTime);

        var entry = NewTitlesOf(_mario)!;
        Assert.Equal(NewTitlesCollector.MaxLines, entry.Movies!.Count);
        Assert.Equal("Film 000", entry.Movies[0].Name);
        Assert.Empty(entry.Series!);
        Assert.Equal(3, entry.More);
    }

    [Fact]
    public void TurningTheSettingOffDropsTheWave()
    {
        _collector.Added(AddMovie("Dune"));
        Assert.Equal(1, _collector.Pending);

        _server.NotifyNewTitles = false;
        Assert.Equal(0, _collector.Pending);
        _collector.Added(AddMovie("Alien"));
        _server.NotifyNewTitles = true;
        _time.Advance(TimeSpan.FromMinutes(30));

        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void ASettingTurnedOffBeforeTheCloseDropsTheWaveToo()
    {
        _collector.Added(AddMovie("Dune"));
        _server.NotifyNewTitles = false;

        _time.Advance(NewTitlesCollector.QuietTime);
        _server.NotifyNewTitles = true;

        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public async Task SendNowClosesAtOnceEvenDuringAScan()
    {
        _server.ScanRunning = true;
        _collector.Added(AddMovie("Dune"));
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));

        var result = await _collector.SendNowAsync();

        Assert.Equal(new NewTitlesSendResponse(2, 2), result);
        Assert.Single(NewTitlesOf(_mario)!.Series!);
        Assert.Empty(NewTitlesOf(_luigi)!.Series!);
        Assert.Equal(new NewTitlesSendResponse(0, 0), await _collector.SendNowAsync());
    }

    [Fact]
    public void ALibraryErrorIsRetriedAtTheNextCheck()
    {
        _collector.Added(AddMovie("Dune"));
        _server.LibraryFails = true;
        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));

        _server.LibraryFails = false;
        _time.Advance(NewTitlesCollector.CheckInterval);

        Assert.NotNull(NewTitlesOf(_mario));
    }

    [Fact]
    public void AWaveWhoseCloseFailsAfterTheDetachIsKeptAndRetried()
    {
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));
        _collector.Added(AddMovie("Dune"));
        // Le serie seguite si leggono dopo che l'ondata si è staccata.
        _server.OnFollowsSeries = () =>
        {
            _server.OnFollowsSeries = null;
            throw new InvalidOperationException("libreria non disponibile");
        };

        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(2, _collector.Pending);

        _time.Advance(NewTitlesCollector.CheckInterval);

        var entry = NewTitlesOf(_mario)!;
        Assert.Equal(new[] { "Dune" }, entry.Movies!.Select(m => m.Name));
        Assert.Single(entry.Series!);
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void TitlesAddedOrRemovedWhileACloseFailsAreKept()
    {
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));
        var dune = AddMovie("Dune");
        _collector.Added(dune);
        var alien = AddMovie("Alien");
        _server.OnFollowsSeries = () =>
        {
            _server.OnFollowsSeries = null;
            // Arrivano mentre l'ondata è staccata: aprono la prossima, che poi si fonde con quella rimessa.
            _collector.Added(alien);
            _collector.Removed(dune, isMovie: true, []);
            throw new InvalidOperationException("libreria non disponibile");
        };

        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(2, _collector.Pending);

        // Alien ha appena cambiato l'ondata: si aspetta di nuovo la quiete.
        Wait(NewTitlesCollector.QuietTime);

        var entry = NewTitlesOf(_mario)!;
        Assert.Equal(new[] { "Alien" }, entry.Movies!.Select(m => m.Name));
        Assert.Single(entry.Series!);
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void AWaveThatKeepsFailingIsDroppedAfterTheLastAttempt()
    {
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));
        _collector.Added(AddMovie("Dune"));
        _server.OnFollowsSeries = () => throw new InvalidOperationException("libreria non disponibile");

        // Il primo tentativo dopo la quiete, poi uno a ogni controllo.
        Wait(NewTitlesCollector.QuietTime);
        Wait(NewTitlesCollector.CheckInterval * (NewTitlesCollector.MaxCloseAttempts - 2));
        Assert.Equal(2, _collector.Pending);

        _time.Advance(NewTitlesCollector.CheckInterval);
        Assert.Equal(0, _collector.Pending);
        var warning = Assert.Single(_log.Entries, e => e.Level == LogLevel.Warning && e.Exception is null);
        Assert.DoesNotContain("Dune", warning.Message, StringComparison.Ordinal);

        _server.OnFollowsSeries = null;
        _time.Advance(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
    }

    [Fact]
    public void OnlyFailuresInARowDropTheWave()
    {
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));
        _collector.Added(AddMovie("Dune"));
        _server.OnFollowsSeries = () => throw new InvalidOperationException("libreria non disponibile");
        Wait(NewTitlesCollector.QuietTime);
        Wait(NewTitlesCollector.CheckInterval * (NewTitlesCollector.MaxCloseAttempts - 2));

        // Un controllo senza errori (durante una scansione si aspetta): il conto riparte.
        _server.ScanRunning = true;
        _time.Advance(NewTitlesCollector.CheckInterval);
        _server.ScanRunning = false;
        Wait(NewTitlesCollector.CheckInterval * (NewTitlesCollector.MaxCloseAttempts - 1));
        Assert.Equal(2, _collector.Pending);

        _time.Advance(NewTitlesCollector.CheckInterval);
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void AWaveDroppedWhileItsCloseFailsDoesNotComeBack()
    {
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));
        _collector.Added(AddMovie("Dune"));
        _server.OnFollowsSeries = () =>
        {
            _server.OnFollowsSeries = null;
            // Casella spenta (e riaccesa) mentre l'ondata è staccata, poi l'errore.
            _server.NotifyNewTitles = false;
            Assert.Equal(0, _collector.Pending);
            _server.NotifyNewTitles = true;
            throw new InvalidOperationException("libreria non disponibile");
        };

        Wait(NewTitlesCollector.QuietTime);
        Assert.Equal(0, _collector.Pending);

        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
        Assert.DoesNotContain(_log.Entries, e => e.Message.Contains("Dune", StringComparison.Ordinal));
    }

    [Fact]
    public async Task DisposingDuringACheckDoesNotTurnItIntoAFailure()
    {
        _collector.Added(AddMovie("Dune"));
        using var inside = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        _server.OnGet = _ =>
        {
            _server.OnGet = null;
            inside.Set();
            release.Wait(TimeSpan.FromSeconds(10));
        };
        Wait(NewTitlesCollector.QuietTime - NewTitlesCollector.CheckInterval);

        // Il plugin si ferma mentre un controllo sta chiudendo l'ondata.
        var check = Task.Run(() => _time.Advance(NewTitlesCollector.CheckInterval));
        try
        {
            Assert.True(inside.Wait(TimeSpan.FromSeconds(10)));
            _collector.Dispose();
            release.Set();
            await check;
        }
        finally
        {
            release.Set();
        }

        Assert.NotNull(NewTitlesOf(_mario));
        Assert.DoesNotContain(_log.Entries, e => e.Level >= LogLevel.Warning);
    }

    [Fact]
    public async Task SendNowWaitsForACheckInProgress()
    {
        _collector.Added(AddMovie("dune.2021.mkv", refreshed: false));
        using var inside = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        _server.OnGet = _ =>
        {
            _server.OnGet = null;
            inside.Set();
            release.Wait(TimeSpan.FromSeconds(10));
        };
        Wait(NewTitlesCollector.QuietTime - NewTitlesCollector.CheckInterval);

        // Il controllo del timer, su un altro thread, si ferma mentre legge la libreria.
        var check = Task.Run(() => _time.Advance(NewTitlesCollector.CheckInterval));
        try
        {
            Assert.True(inside.Wait(TimeSpan.FromSeconds(10)));
            var send = _collector.SendNowAsync();
            Assert.False(send.IsCompleted);

            // Il controllo trova un titolo senza metadati e lascia l'ondata: "Send now" la chiude.
            release.Set();
            await check;
            Assert.Equal(new NewTitlesSendResponse(1, 2), await send);
        }
        finally
        {
            release.Set();
        }
    }

    [Fact]
    public void AWaveDroppedDuringItsCloseIsNotSent()
    {
        _collector.Added(AddMovie("Dune"));
        var alien = AddMovie("Alien");
        _server.OnGet = _ =>
        {
            _server.OnGet = null;
            // Casella spenta e riaccesa mentre si legge la libreria: l'ondata si butta e ne comincia un'altra.
            _server.NotifyNewTitles = false;
            Assert.Equal(0, _collector.Pending);
            _server.NotifyNewTitles = true;
            _collector.Added(alien);
        };

        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(1, _collector.Pending);

        Wait(NewTitlesCollector.QuietTime);
        Assert.Equal(new[] { "Alien" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void ATitleArrivingDuringTheCloseWaitsForQuietAgain()
    {
        _collector.Added(AddMovie("Dune"));
        var alien = AddMovie("Alien");
        _server.OnGet = _ =>
        {
            _server.OnGet = null;
            _collector.Added(alien);
        };

        Wait(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(2, _collector.Pending);

        Wait(NewTitlesCollector.QuietTime);
        Assert.Equal(new[] { "Alien", "Dune" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void AnOverdueWaveClosesEvenIfATitleArrivesDuringTheClose()
    {
        // Con le novità continue di un grande import l'ondata deve chiudersi comunque entro MaxWait.
        _server.ScanRunning = true;
        _collector.Added(AddMovie("Dune"));
        Wait(NewTitlesCollector.MaxWait - NewTitlesCollector.CheckInterval);
        var alien = AddMovie("Alien");
        _server.OnGet = _ =>
        {
            _server.OnGet = null;
            _collector.Added(alien);
        };

        _time.Advance(NewTitlesCollector.CheckInterval);

        Assert.Equal(new[] { "Alien", "Dune" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void WaitingForMetadataStopsAtTheFirstTitleWithout()
    {
        for (var i = 0; i < 3; i++)
        {
            _collector.Added(AddMovie($"film.{i}.mkv", refreshed: false));
        }

        var reads = 0;
        _server.OnGet = _ => reads++;

        Wait(NewTitlesCollector.QuietTime);

        Assert.Equal(1, reads);
        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(3, _collector.Pending);
    }

    [Fact]
    public void AReplacementSpanningTwoWavesIsAnnounced()
    {
        // Limite accettato: una sostituzione si riconosce solo se il vecchio
        // file è tolto nella stessa ondata in cui arriva il nuovo.
        _collector.Removed(Guid.NewGuid(), isMovie: true, ["Tmdb:438631"]);
        _time.Advance(NewTitlesCollector.QuietTime);

        _collector.Added(AddMovie("Dune", keys: ["Tmdb:438631"]));
        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Single(NewTitlesOf(_mario)!.Movies!);
    }

    [Fact]
    public void BeyondTheLimitMoviesComeFirstSeriesFillTheRestAndMoreCountsBoth()
    {
        var movies = new List<Guid>();
        for (var i = 0; i < NewTitlesCollector.MaxLines + 1; i++)
        {
            var movie = AddMovie($"Film {i:000}");
            movies.Add(movie);
            _collector.Added(movie);
        }

        foreach (var name in new[] { "E", "D", "C", "B", "A" })
        {
            var seriesId = Guid.NewGuid();
            _server.Following.Add((_mario.Id, seriesId));
            _server.Following.Add((_luigi.Id, seriesId));
            _collector.Added(AddEpisode(seriesId, 1, 1, seriesName: name));
        }

        // Luigi non vede tre film: gli restano righe per due serie.
        foreach (var movie in movies.Take(3))
        {
            _server.Unseen.Add((_luigi.Id, movie));
        }

        _time.Advance(NewTitlesCollector.QuietTime);

        var mario = NewTitlesOf(_mario)!;
        Assert.Equal(NewTitlesCollector.MaxLines, mario.Movies!.Count);
        Assert.Empty(mario.Series!);
        Assert.Equal(6, mario.More);
        var luigi = NewTitlesOf(_luigi)!;
        Assert.Equal(NewTitlesCollector.MaxLines - 2, luigi.Movies!.Count);
        Assert.Equal(new[] { "A", "B" }, luigi.Series!.Select(s => s.Name));
        Assert.Equal(3, luigi.More);
    }
}
