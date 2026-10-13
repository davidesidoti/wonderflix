using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ActivityBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 13, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ATitleIsKeptOnceWithItsLatestDate()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        var dune = Guid.NewGuid();
        var bear = Guid.NewGuid();

        Assert.True(book.Record(user, dune, Now));
        book.Record(user, bear, Now.AddMinutes(1));
        book.Record(user, dune, Now.AddMinutes(2));

        Assert.Equal(
            new[] { new WatchedTitle(dune, Now.AddMinutes(2)), new WatchedTitle(bear, Now.AddMinutes(1)) },
            book.Views(user));
        Assert.Empty(book.Views(Guid.NewGuid()));
    }

    [Fact]
    public void OverTheCapTheOldestTitleLeaves()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        var first = Guid.NewGuid();
        book.Record(user, first, Now);
        for (var i = 1; i <= ActivityBook.MaxTitles; i++)
        {
            book.Record(user, Guid.NewGuid(), Now.AddMinutes(i));
        }

        var views = book.Views(user);
        Assert.Equal(ActivityBook.MaxTitles, views.Count);
        Assert.DoesNotContain(views, v => v.ItemId == first);
    }

    [Fact]
    public void TurningSharingOffDeletesTheViewsAndStopsRecording()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        Assert.True(book.Shares(user));
        book.Record(user, Guid.NewGuid(), Now);

        Assert.True(book.SetShare(user, false));
        Assert.False(book.Shares(user));
        Assert.Empty(book.Views(user));
        Assert.False(book.Record(user, Guid.NewGuid(), Now));
        Assert.Empty(book.Views(user));
        Assert.False(book.SetShare(user, false));

        // Riaccesa: si registra di nuovo, ma le visioni cancellate non tornano.
        Assert.True(book.SetShare(user, true));
        Assert.True(book.Shares(user));
        Assert.Empty(book.Views(user));
        Assert.False(book.SetShare(user, true));
    }

    [Fact]
    public void PruneDropsOldViewsAndMissingUsers()
    {
        var book = new ActivityBook();
        var mario = Guid.NewGuid();
        var gone = Guid.NewGuid();
        var hiddenGone = Guid.NewGuid();
        var old = Guid.NewGuid();
        var recent = Guid.NewGuid();
        book.Record(mario, old, Now.AddDays(-31));
        book.Record(mario, recent, Now.AddDays(-1));
        book.Record(gone, recent, Now);
        book.SetShare(hiddenGone, false);

        // La visione vecchia, quella di chi non c'è più e la scelta di chi non c'è più.
        Assert.Equal(3, book.Prune(Now.AddDays(-30), id => id == mario));
        Assert.Equal(new[] { new WatchedTitle(recent, Now.AddDays(-1)) }, book.Views(mario));
        Assert.Empty(book.Views(gone));
        Assert.True(book.Shares(hiddenGone));
        Assert.Equal(0, book.Prune(Now.AddDays(-30), id => id == mario));
    }

    [Fact]
    public void TheFileRoundTrips()
    {
        var book = new ActivityBook();
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var dune = Guid.NewGuid();
        book.Record(mario, dune, Now);
        book.SetShare(luigi, false);

        var file = book.ToFile();
        var copy = ActivityBook.FromFile(JsonSerializer.Deserialize<ActivityFile>(JsonSerializer.Serialize(file))!);

        Assert.Equal(book.Views(mario), copy.Views(mario));
        Assert.False(copy.Shares(luigi));
        Assert.True(copy.Shares(mario));
        Assert.Equal(dune.ToString("N"), file.Users![mario.ToString("N")]![0]!.ItemId);
        Assert.Equal(new[] { luigi.ToString("N") }, file.Hidden);
    }

    [Fact]
    public void AHiddenUserInTheFileHasNoViews()
    {
        var mario = Guid.NewGuid().ToString("N");
        var file = new ActivityFile
        {
            Hidden = [mario],
            Users = new() { [mario] = [new ActivityFileView { ItemId = Guid.NewGuid().ToString("N"), WatchedAt = Now }] },
        };

        var book = ActivityBook.FromFile(file);

        Assert.Empty(book.Views(Guid.Parse(mario)));
        Assert.False(book.Shares(Guid.Parse(mario)));
    }

    [Theory]
    [InlineData("{\"Users\":{\"x\":[]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":[{\"ItemId\":\"y\"}]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":[null]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":null}}")]
    [InlineData("{\"Hidden\":[\"x\"]}")]
    [InlineData("{\"Hidden\":[null]}")]
    public void ABrokenFileIsAFormatError(string json) =>
        Assert.Throws<FormatException>(() => ActivityBook.FromFile(JsonSerializer.Deserialize<ActivityFile>(json)!));
}
