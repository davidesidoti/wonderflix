using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ReportServiceTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly RecordingLogger<ReportService> _log = new();
    private readonly ReportService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly UserRef _daisy;
    private readonly UserRef _toad;
    private readonly InboxService _inbox;
    private readonly ReportedItem _movie;
    private readonly ReportedItem _series;
    private readonly ReportedItem _season;
    private readonly ReportedItem _episode;

    public ReportServiceTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _service = TestReports.Create(_server, _folder, _time, _inbox, _log);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach", isAdmin: true);
        _daisy = _server.AddUser("Daisy", enabled: false, isAdmin: true);
        _toad = _server.AddUser("Toad", canManageSubtitles: true);
        _movie = _server.AddMovie("Dune");
        (_series, _season, _episode) = _server.AddEpisode("Breaking Bad", 2, 3);
    }

    public void Dispose() => _folder.Dispose();

    private static string N(Guid id) => id.ToString("N");

    private static CreateReportRequest Request(Guid itemId, string type, string? note) =>
        new() { ItemId = N(itemId), Type = type, Note = note };

    [Fact]
    public async Task ACreatedReportHasTheTitleAndLevel()
    {
        var outcome = await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, "  Mancano\ni sottotitoli "));
        Assert.Equal(HubStatus.Ok, outcome.Status);
        var dto = outcome.Report!;
        Assert.Equal("Mancano i sottotitoli", dto.Note);
        Assert.Equal(("Episode", N(_series.Id), "Breaking Bad", 2, 3), (dto.ItemType, dto.TitleId, dto.TitleName, dto.SeasonNumber, dto.EpisodeNumber));
        Assert.Equal(("Mario", N(_mario.Id), T0, T0), (dto.UserName, dto.UserId, dto.CreatedAt, dto.UpdatedAt));
        Assert.Equal(dto, Assert.Single(_service.List().Items));
    }

    [Fact]
    public async Task ADuplicateUpdatesTheNote()
    {
        var first = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, "Titolo in arabo"))).Report!;
        _time.Advance(TimeSpan.FromHours(1));
        var again = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null))).Report!;
        Assert.Equal(first.Id, again.Id);
        Assert.Null(again.Note);
        Assert.Equal(T0.AddHours(1), again.UpdatedAt);
        Assert.Equal(T0, again.CreatedAt);
        Assert.Single(_service.List().Items);
    }

    [Fact]
    public async Task TheTwentyFirstOpenReportIsRefused()
    {
        for (var i = 0; i < 20; i++)
        {
            Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_mario.Id, Request(_server.AddMovie($"Film {i}").Id, ReportTypes.Other, null))).Status);
        }

        var outcome = await _service.CreateAsync(_mario.Id, Request(_server.AddMovie("Ultimo").Id, ReportTypes.Other, null));
        Assert.Equal((HubStatus.Conflict, ReportReasons.LimitReached), (outcome.Status, outcome.Reason));

        // Un doppione di una delle 20 resta ammesso, e un altro utente ha il suo limite.
        var first = _server.ReportedItems.Values.First(i => i.Name == "Film 0");
        Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_mario.Id, Request(first.Id, ReportTypes.Other, "Ancora"))).Status);
        Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_luigi.Id, Request(first.Id, ReportTypes.Other, null))).Status);
    }

    [Fact]
    public async Task NotesAreCleanedAndCountedInCodePoints()
    {
        var emoji = string.Concat(Enumerable.Repeat("🎬", 500));
        Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Other, emoji))).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, emoji + "a"))).Status);
        Assert.Equal("a b c", (await _service.CreateAsync(_luigi.Id, Request(_movie.Id, ReportTypes.Other, "a\tb\r\nc"))).Report!.Note);
    }

    [Fact]
    public async Task InvalidRequestsAreRefused()
    {
        _server.Unseen.Add((_mario.Id, _movie.Id));
        var requests = new (Guid User, CreateReportRequest? Request)[]
        {
            (_mario.Id, null),
            (_mario.Id, new CreateReportRequest { ItemId = "boh", Type = ReportTypes.Other }),
            (_mario.Id, new CreateReportRequest { ItemId = null, Type = ReportTypes.Other }),
            (_mario.Id, new CreateReportRequest { ItemId = N(Guid.Empty), Type = ReportTypes.Other }),
            (_mario.Id, Request(_episode.Id, "Boh", null)),
            (_mario.Id, Request(_episode.Id, null!, null)),
            (_mario.Id, Request(Guid.NewGuid(), ReportTypes.Other, null)),
            (_mario.Id, Request(_movie.Id, ReportTypes.Other, null)),
            (Guid.Empty, Request(_episode.Id, ReportTypes.Other, null)),
            (Guid.NewGuid(), Request(_episode.Id, ReportTypes.Other, null)),
        };
        foreach (var (user, request) in requests)
        {
            Assert.Equal(HubStatus.Invalid, (await _service.CreateAsync(user, request)).Status);
        }

        _server.ReportLibraryFails = true;
        Assert.Equal(HubStatus.Invalid, (await _service.CreateAsync(_luigi.Id, Request(_episode.Id, ReportTypes.Other, null))).Status);
        Assert.Contains(_log.Entries, e => e.Level == LogLevel.Warning && e.Message.Contains(N(_episode.Id), StringComparison.Ordinal));

        _server.ReportLibraryFails = false;
        Assert.Empty(_service.List().Items);
        Assert.False(File.Exists(_folder.ReportsFile));
    }

    [Fact]
    public async Task MineHasOnlyTheCallersReportsOnThatItem()
    {
        var mine = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null))).Report!;
        _time.Advance(TimeSpan.FromMinutes(1));
        var other = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Other, "Altro"))).Report!;
        await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
        await _service.CreateAsync(_luigi.Id, Request(_movie.Id, ReportTypes.Metadata, null));

        var result = _service.Mine(_mario.Id, N(_movie.Id));

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal([other, mine], result.Value!.Items);
        Assert.Equal(HubStatus.Invalid, _service.Mine(_mario.Id, "boh").Status);
        Assert.Equal(HubStatus.Invalid, _service.Mine(_mario.Id, null).Status);
        Assert.Equal(HubStatus.Invalid, _service.Mine(Guid.Empty, N(_movie.Id)).Status);
        Assert.Empty(_service.Mine(_luigi.Id, N(_series.Id)).Value!.Items);
    }

    [Fact]
    public async Task ListShowsEmptyNamesForAGoneTitle()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, "Nota"));
        _server.ReportedItems.Remove(_movie.Id);

        var dto = Assert.Single(_service.List().Items);

        Assert.Equal(("", "", "", N(_movie.Id), N(_movie.Id)), (dto.ItemType, dto.ItemName, dto.TitleName, dto.ItemId, dto.TitleId));
        Assert.Equal("Nota", dto.Note);
    }

    [Fact]
    public async Task ListWarnsOnceWhenTheLibraryFails()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null));
        await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
        _server.ReportLibraryFails = true;
        _log.Entries.Clear();

        var items = _service.List().Items;

        Assert.Equal(2, items.Count);
        Assert.All(items, i => Assert.Equal((string.Empty, i.ItemId), (i.ItemName, i.TitleId)));
        Assert.Single(_log.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public async Task ListIsNewestFirstWithTheUserName()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null));
        _time.Advance(TimeSpan.FromMinutes(1));
        await _service.CreateAsync(_luigi.Id, Request(_episode.Id, ReportTypes.Subtitles, null));

        Assert.Equal(["Luigi", "Mario"], _service.List().Items.Select(i => i.UserName));
    }

    [Fact]
    public async Task ResolveRemovesTheReport()
    {
        var report = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null))).Report!;

        Assert.Equal(HubStatus.Invalid, (await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = "Boh" })).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.ResolveAsync(_peach.Id, "boh", new ResolveReportRequest { Outcome = ReportOutcomes.Fixed })).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.ResolveAsync(_peach.Id, report.Id, null)).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed, Note = new string('a', 501) })).Status);
        Assert.Single(_service.List().Items);

        var outcome = await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed, Note = "Segreto dell'admin" });

        Assert.Equal((HubStatus.Ok, null), (outcome.Status, outcome.Report));
        Assert.Empty(_service.List().Items);
        var entry = Assert.Single(_log.Entries, e => e.Level == LogLevel.Information && e.Message.Contains("chiusa", StringComparison.Ordinal));
        Assert.Contains(report.Id, entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Segreto", entry.Message, StringComparison.Ordinal);

        var again = await _service.ResolveAsync(Guid.Empty, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.CannotFix });
        Assert.Equal((HubStatus.Conflict, ReportReasons.Closed), (again.Status, again.Reason));
    }

    [Fact]
    public async Task CleanupKeepsReportsDuringAScanOrALibraryError()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null));
        await _service.CreateAsync(_luigi.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
        _server.ReportedItems.Remove(_movie.Id);

        _server.ScanRunning = true;
        Assert.Equal(0, _service.Cleanup());
        Assert.Equal(2, _service.List().Items.Count);

        _server.ScanRunning = false;
        _server.ReportLibraryFails = true;
        _log.Entries.Clear();
        Assert.Equal(0, _service.Cleanup());
        Assert.Single(_log.Entries, e => e.Level == LogLevel.Warning);

        _server.ReportLibraryFails = false;
        _server.Users.Remove(_luigi.Id);
        Assert.Equal(2, _service.Cleanup());
        Assert.Empty(_service.List().Items);
    }

    [Fact]
    public async Task CleanupRemovesAGoneUserAndKeepsTheRest()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null));
        await _service.CreateAsync(_luigi.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(1, _service.Cleanup());

        Assert.Equal(_mario.Id, Guid.ParseExact(Assert.Single(_service.List().Items).UserId, "N"));
    }

    [Fact]
    public async Task PendingGoesToEnabledAdminsOnly()
    {
        await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
        Assert.Equal(InboxEntryTypes.ReportPending, Assert.Single(_inbox.Get(_peach.Id).Entries).Type);
        Assert.Empty(_inbox.Get(_daisy.Id).Entries);
        Assert.Empty(_inbox.Get(_toad.Id).Entries);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
    }

    [Fact]
    public async Task ResolvingNotifiesTheReporterAndClearsTheAdmins()
    {
        var report = (await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null))).Report!;
        var outcome = await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed, Note = "Aggiunti" });
        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Empty(_inbox.Get(_peach.Id).Entries);
        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal((InboxEntryTypes.ReportResolved, ReportOutcomes.Fixed, "Aggiunti"), (entry.Type, entry.Outcome, entry.Text));
    }

    [Fact]
    public async Task TheResolvedNoteIsTheCleanedOne()
    {
        var report = (await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null))).Report!;
        await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed, Note = "  Aggiunti\ni sottotitoli " });
        Assert.Equal("Aggiunti i sottotitoli", Assert.Single(_inbox.Get(_mario.Id).Entries).Text);
    }

    [Fact]
    public async Task ResolvingWithAGoneTitleStillNotifiesTheReporter()
    {
        var report = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null))).Report!;
        _server.ReportedItems.Remove(_movie.Id);
        await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.CannotFix });
        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal((N(_movie.Id), ""), (entry.ItemId, entry.Title));
    }

    [Fact]
    public async Task ASecondResolveIsClosedAndNotifiesOnce()
    {
        var rosalina = _server.AddUser("Rosalina", isAdmin: true);
        var report = (await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null))).Report!;
        var fixedIt = new ResolveReportRequest { Outcome = ReportOutcomes.Fixed };

        Assert.Equal(HubStatus.Ok, (await _service.ResolveAsync(_peach.Id, report.Id, fixedIt)).Status);
        var second = await _service.ResolveAsync(rosalina.Id, report.Id, fixedIt);

        Assert.Equal((HubStatus.Conflict, ReportReasons.Closed), (second.Status, second.Reason));
        Assert.Single(_inbox.Get(_mario.Id).Entries, e => e.Type == InboxEntryTypes.ReportResolved);
        Assert.Empty(_inbox.Get(rosalina.Id).Entries);
    }

    [Fact]
    public async Task AnAdminReportingHimselfGetsNoEntries()
    {
        var rosalina = _server.AddUser("Rosalina", isAdmin: true);
        var report = (await _service.CreateAsync(_peach.Id, Request(_episode.Id, ReportTypes.Subtitles, null))).Report!;
        Assert.Empty(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(InboxEntryTypes.ReportPending, Assert.Single(_inbox.Get(rosalina.Id).Entries).Type);

        await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed });

        Assert.Empty(_inbox.Get(rosalina.Id).Entries);
        Assert.Empty(_inbox.Get(_peach.Id).Entries);
    }

    [Fact]
    public async Task ADuplicateDoesNotNotifyAgain()
    {
        _server.AddSession("s-peach", _peach);
        await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, "Uno"));
        await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, "Due"));

        Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Single(_server.SentTo("s-peach"));
    }

    [Fact]
    public async Task CleanupClearsThePendingEntries()
    {
        await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null));
        Assert.Single(_inbox.Get(_peach.Id).Entries);
        _server.ReportedItems.Remove(_movie.Id);

        Assert.Equal(1, _service.Cleanup());

        Assert.Empty(_inbox.Get(_peach.Id).Entries);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
    }

    [Fact]
    public async Task ADiskErrorKeepsTheReportInMemory()
    {
        Directory.CreateDirectory(_folder.ReportsFile);

        var outcome = await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Other, null));

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Single(_service.List().Items);
        Assert.Contains(_log.Entries, e => e.Level == LogLevel.Warning);
    }
}
