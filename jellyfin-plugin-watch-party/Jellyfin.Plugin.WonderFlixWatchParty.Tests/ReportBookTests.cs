using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ReportBookTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _episode = Guid.NewGuid();
    private readonly Guid _movie = Guid.NewGuid();

    private static StoredReport Report(Guid user, Guid item, string type, DateTimeOffset at) =>
        new(Guid.NewGuid(), user, item, type, null, at, at);

    [Fact]
    public void FindOpenMatchesUserItemAndType()
    {
        var book = new ReportBook();
        var report = Report(_mario, _episode, ReportTypes.Subtitles, T0);
        book.Add(report);
        Assert.Equal(report, book.FindOpen(_mario, _episode, ReportTypes.Subtitles));
        Assert.Null(book.FindOpen(_mario, _episode, ReportTypes.Metadata));
        Assert.Null(book.FindOpen(_luigi, _episode, ReportTypes.Subtitles));
        Assert.Equal(1, book.CountOpen(_mario));
        Assert.Equal(0, book.CountOpen(_luigi));
    }

    [Fact]
    public void UpdateNoteKeepsCreatedAt()
    {
        var book = new ReportBook();
        var report = Report(_mario, _episode, ReportTypes.Subtitles, T0) with { Note = "vecchia" };
        book.Add(report);
        var updated = book.UpdateNote(report.Id, null, T0.AddHours(1));
        Assert.Equal(report with { Note = null, UpdatedAt = T0.AddHours(1) }, updated);
        Assert.Equal(updated, book.Get(report.Id));
    }

    [Fact]
    public void ListsAreNewestFirst()
    {
        var book = new ReportBook();
        var first = Report(_mario, _episode, ReportTypes.Subtitles, T0);
        var second = Report(_luigi, _episode, ReportTypes.Metadata, T0.AddHours(1));
        var third = Report(_mario, _episode, ReportTypes.Other, T0.AddHours(2));
        book.Add(first);
        book.Add(second);
        book.Add(third);
        Assert.Equal([third, second, first], book.All());
        Assert.Equal([third, first], book.ForUser(_mario, _episode));
        Assert.Empty(book.ForUser(_mario, _movie));
    }

    [Fact]
    public void RemoveReportsWhetherItWasThere()
    {
        var book = new ReportBook();
        var report = Report(_mario, _episode, ReportTypes.Subtitles, T0);
        book.Add(report);
        Assert.True(book.Remove(report.Id));
        Assert.False(book.Remove(report.Id));
        Assert.Null(book.Get(report.Id));
    }

    [Fact]
    public void PruneReturnsTheRemovedReports()
    {
        var book = new ReportBook();
        book.Add(Report(_mario, _episode, ReportTypes.Subtitles, T0));
        book.Add(Report(_luigi, _episode, ReportTypes.Subtitles, T0));
        book.Add(Report(_mario, _movie, ReportTypes.Subtitles, T0));

        var removed = book.Prune(user => user != _luigi, item => item != _movie);

        Assert.Equal(2, removed.Count);
        Assert.Equal(_mario, Assert.Single(book.All()).UserId);
    }
}
