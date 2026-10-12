using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RecommendationBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 12, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly Guid _dune = Guid.NewGuid();
    private readonly Guid _bear = Guid.NewGuid();

    [Fact]
    public void TitlesAreListedNewestFirstWithTheirSendersNewestFirst()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _bear, _mario, null, Now.AddMinutes(1));
        book.Add(_luigi, _dune, _peach, "bellissimo", Now.AddMinutes(2));

        var titles = book.List(_luigi);

        Assert.Equal(new[] { _dune, _bear }, titles.Select(t => t.ItemId));
        Assert.Equal(new[] { _peach, _mario }, titles[0].From.Select(f => f.UserId));
        Assert.Equal(Now.AddMinutes(2), titles[0].LatestAt);
        Assert.Null(titles[1].From[0].Message);
        Assert.Empty(book.List(_mario));
    }

    [Fact]
    public void RecommendingAgainUpdatesMessageAndDateWithoutDuplicates()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _dune, _mario, null, Now.AddDays(1));

        var sender = Assert.Single(Assert.Single(book.List(_luigi)).From);
        Assert.Null(sender.Message);
        Assert.Equal(Now.AddDays(1), sender.CreatedAt);
    }

    [Fact]
    public void AtMost50TitlesTheOldestGoes()
    {
        var book = new RecommendationBook();
        var items = Enumerable.Range(0, RecommendationBook.MaxTitles + 1).Select(_ => Guid.NewGuid()).ToList();
        for (var i = 0; i < items.Count; i++)
        {
            book.Add(_luigi, items[i], _mario, null, Now.AddMinutes(i));
        }

        var titles = book.List(_luigi);
        Assert.Equal(RecommendationBook.MaxTitles, titles.Count);
        Assert.DoesNotContain(items[0], titles.Select(t => t.ItemId));
        Assert.Equal(items[^1], titles[0].ItemId);
    }

    [Fact]
    public void RemoveSenderDropsTheTitleOnlyWithoutSendersLeft()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        book.Add(_luigi, _dune, _peach, null, Now);

        Assert.True(book.RemoveSender(_luigi, _dune, _mario, Now));
        Assert.Equal(_peach, Assert.Single(Assert.Single(book.List(_luigi)).From).UserId);
        Assert.False(book.RemoveSender(_luigi, _dune, _mario, Now));
        Assert.True(book.RemoveSender(_luigi, _dune, _peach, Now));
        Assert.Empty(book.List(_luigi));
        Assert.False(book.RemoveSender(_mario, _dune, _peach, Now));
    }

    [Fact]
    public void RemoveSenderKeepsASenderAddedAgainMeanwhile()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        book.Add(_luigi, _dune, _mario, "di nuovo", Now.AddMinutes(1));

        Assert.False(book.RemoveSender(_luigi, _dune, _mario, Now));
        Assert.Single(Assert.Single(book.List(_luigi)).From);
    }

    [Fact]
    public void RemoveIfLatestKeepsATitleRecommendedAgainMeanwhile()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        var seen = Assert.Single(book.List(_luigi)).LatestAt;

        // Peach consiglia Dune mentre GET sta ancora controllando la visione di prima.
        book.Add(_luigi, _dune, _peach, null, Now.AddMinutes(5));

        Assert.False(book.RemoveIfLatest(_luigi, _dune, seen));
        Assert.Single(book.List(_luigi));
        Assert.True(book.RemoveIfLatest(_luigi, _dune, Now.AddMinutes(5)));
        Assert.Empty(book.List(_luigi));
    }

    [Fact]
    public void RemoveDropsTheTitleForThatUserOnly()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        book.Add(_peach, _dune, _mario, null, Now);

        Assert.True(book.Remove(_luigi, _dune));
        Assert.False(book.Remove(_luigi, _dune));
        Assert.Empty(book.List(_luigi));
        Assert.Single(book.List(_peach));
    }

    [Fact]
    public void PruneDropsOldTitlesLostSendersAndMissingUsers()
    {
        var book = new RecommendationBook();
        var gone = Guid.NewGuid();
        book.Add(_luigi, _dune, _mario, null, Now.AddDays(-70));
        book.Add(_luigi, _dune, _peach, null, Now.AddDays(-10)); // la data del titolo è questa: resta
        book.Add(_luigi, _bear, _mario, null, Now.AddDays(-61));
        book.Add(gone, _bear, _mario, null, Now);

        // Peach non è più amica di Luigi; l'utente "gone" non c'è più.
        var removed = book.Prune(
            Now.AddDays(-60),
            userId => userId != gone,
            (to, from) => from != _peach);

        // Dune perde Peach, poi resta solo il consiglio di 70 giorni fa: esce.
        Assert.Equal(3, removed);
        Assert.Empty(book.List(_luigi));
        Assert.Empty(book.List(gone));
    }

    [Fact]
    public void TheFileKeepsEverythingAndRejectsBrokenEntries()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _dune, _peach, null, Now.AddMinutes(1));

        var copy = RecommendationBook.FromFile(book.ToFile());

        var title = Assert.Single(copy.List(_luigi));
        Assert.Equal(_dune, title.ItemId);
        Assert.Equal(new[] { _peach, _mario }, title.From.Select(f => f.UserId));
        Assert.Equal("da vedere", title.From[1].Message);
        Assert.Null(title.From[0].Message);

        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new() { ["non-un-id"] = [] },
        }));
        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new() { [_luigi.ToString("N")] = [null] },
        }));
        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new()
            {
                [_luigi.ToString("N")] = [new RecommendationFileTitle { ItemId = _dune.ToString("N"), From = [null] }],
            },
        }));
    }
}
