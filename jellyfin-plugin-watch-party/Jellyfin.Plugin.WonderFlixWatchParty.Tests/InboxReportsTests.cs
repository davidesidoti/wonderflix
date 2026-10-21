using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxReportsTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly InboxService _inbox;
    private readonly UserRef _peach;
    private readonly UserRef _rosalina;
    private readonly UserRef _mario;
    private readonly ReportedItem _series;
    private readonly ReportedItem _episode;

    public InboxReportsTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _peach = _server.AddUser("Peach", isAdmin: true);
        _rosalina = _server.AddUser("Rosalina", isAdmin: true);
        _mario = _server.AddUser("Mario");
        _server.AddSession("s-peach", _peach);
        _server.AddSession("s-rosalina", _rosalina);
        _server.AddSession("s-mario", _mario);
        (_series, _, _episode) = _server.AddEpisode("Breaking Bad", 2, 3);
    }

    public void Dispose() => _folder.Dispose();

    private StoredReport Report(string? note = "Mancano") =>
        new(Guid.NewGuid(), _mario.Id, _episode.Id, ReportTypes.Subtitles, note, T0, T0);

    private static string N(Guid id) => id.ToString("N");

    private static string Type(string payload) =>
        JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    [Fact]
    public async Task PendingEntriesCarryTheReport()
    {
        var report = Report();

        await _inbox.AddReportPendingAsync([_peach.Id], report, _episode, "Mario");

        var entry = Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Equal((InboxEntryTypes.ReportPending, N(report.Id), ReportTypes.Subtitles, "Mario", "Mancano"),
            (entry.Type, entry.ReportId, entry.ReportType, entry.FromName, entry.Text));
        Assert.Equal((N(_episode.Id), "Episode", 2, 3, "Breaking Bad", N(_series.Id)),
            (entry.ItemId, entry.ItemType, entry.SeasonNumber, entry.EpisodeNumber, entry.Title, entry.ImageItemId));
        Assert.Null(entry.Outcome);
        Assert.Equal("InboxChanged", Type(Assert.Single(_server.SentTo("s-peach"))));
        Assert.Empty(_server.SentTo("s-mario"));
    }

    [Fact]
    public async Task RemoveReportTouchesOnlyThatReport()
    {
        var a = Report();
        var b = Report("Altro");
        await _inbox.AddReportPendingAsync([_peach.Id, _rosalina.Id], a, _episode, "Mario");
        await _inbox.AddReportPendingAsync([_rosalina.Id], b, _episode, "Mario");
        _server.Sent.Clear();

        await _inbox.RemoveReportEntriesAsync([a.Id]);

        Assert.Empty(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(N(b.Id), Assert.Single(_inbox.Get(_rosalina.Id).Entries).ReportId);
        Assert.Single(_server.SentTo("s-peach"));
        Assert.Single(_server.SentTo("s-rosalina"));
        Assert.Empty(_server.SentTo("s-mario"));

        _server.Sent.Clear();
        await _inbox.RemoveReportEntriesAsync([a.Id]);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task ResolvedEntriesCarryTheOutcomeAndTheNote()
    {
        var report = Report();

        await _inbox.AddReportResolvedAsync(_mario.Id, report, _episode, ReportOutcomes.CannotFix, "Non esistono");

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal((InboxEntryTypes.ReportResolved, N(report.Id), ReportTypes.Subtitles, ReportOutcomes.CannotFix, "Non esistono"),
            (entry.Type, entry.ReportId, entry.ReportType, entry.Outcome, entry.Text));
        Assert.Equal((N(_episode.Id), "Episode", 2, 3, "Breaking Bad", N(_series.Id)),
            (entry.ItemId, entry.ItemType, entry.SeasonNumber, entry.EpisodeNumber, entry.Title, entry.ImageItemId));
        Assert.Null(entry.FromName);
        Assert.Equal("InboxChanged", Type(Assert.Single(_server.SentTo("s-mario"))));
    }

    [Fact]
    public async Task ResolvedWithAGoneTitleHasTheReportItemId()
    {
        var report = Report();

        await _inbox.AddReportResolvedAsync(_mario.Id, report, null, ReportOutcomes.Fixed, null);

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal((N(_episode.Id), ""), (entry.ItemId, entry.Title));
        Assert.Null(entry.ImageItemId);
        Assert.Null(entry.ItemType);
        Assert.Null(entry.SeasonNumber);
        Assert.Null(entry.EpisodeNumber);
        Assert.Null(entry.Text);
    }

    [Fact]
    public async Task TheJsonHasTheNewFieldsOnlyWhenSet()
    {
        await _inbox.AnnounceAsync("Ciao");
        var announcement = Assert.Single(_inbox.Get(_mario.Id).Entries);
        var json = JsonSerializer.Serialize(announcement);
        Assert.DoesNotContain("ReportId", json, StringComparison.Ordinal);
        Assert.DoesNotContain("ReportType", json, StringComparison.Ordinal);
        Assert.DoesNotContain("Outcome", json, StringComparison.Ordinal);
        Assert.DoesNotContain("ItemType", json, StringComparison.Ordinal);
        Assert.DoesNotContain("SeasonNumber", json, StringComparison.Ordinal);
        Assert.DoesNotContain("EpisodeNumber", json, StringComparison.Ordinal);

        await _inbox.AddReportPendingAsync([_peach.Id], Report(), _episode, "Mario");
        var pending = JsonSerializer.Serialize(Assert.Single(_inbox.Get(_peach.Id).Entries, e => e.Type == InboxEntryTypes.ReportPending));
        Assert.Contains("\"SeasonNumber\":2", pending, StringComparison.Ordinal);
        Assert.Contains("\"ItemType\":\"Episode\"", pending, StringComparison.Ordinal);
    }
}
