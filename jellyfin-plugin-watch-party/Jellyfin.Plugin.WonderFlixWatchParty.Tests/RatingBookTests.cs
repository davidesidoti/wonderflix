using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingBookTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 20, 21, 0, 0, TimeSpan.Zero);

    private readonly Guid _film = Guid.NewGuid();
    private readonly Guid _season = Guid.NewGuid();
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();

    [Fact]
    public void AVoteAgainReplacesScoreAndCommentAndKeepsCreatedAt()
    {
        var book = new RatingBook();
        book.Set(_film, _mario, 8, "Capolavoro", T0);
        var again = book.Set(_film, _mario, 6, null, T0.AddDays(1));
        Assert.Equal(new StoredRating(_mario, 6, null, T0, T0.AddDays(1)), again);
        Assert.Equal(again, book.Get(_film, _mario));
        Assert.Single(book.ForItem(_film));
    }

    [Fact]
    public void RemovingTheCommentKeepsScoreAndUpdatedAt()
    {
        var book = new RatingBook();
        book.Set(_film, _mario, 8, "Capolavoro", T0);
        Assert.True(book.RemoveComment(_film, _mario));
        Assert.Equal(new StoredRating(_mario, 8, null, T0, T0), book.Get(_film, _mario));
        Assert.False(book.RemoveComment(_film, _luigi));
        Assert.True(book.Remove(_film, _mario));
        Assert.Null(book.Get(_film, _mario));
        Assert.False(book.Remove(_film, _mario));
    }

    [Fact]
    public void CommentsAreNewestFirstBeforeADate()
    {
        var book = new RatingBook();
        book.Set(_film, _mario, 8, "a", T0);
        book.Set(_film, _luigi, 7, "b", T0.AddHours(1));
        book.Set(_season, _mario, 9, null, T0.AddHours(2));
        Assert.Equal(new[] { _luigi, _mario }, book.Comments(null, 50).Select(c => c.Rating.UserId));
        Assert.Equal(_mario, Assert.Single(book.Comments(T0.AddHours(1), 50)).Rating.UserId);
        Assert.Equal(_luigi, Assert.Single(book.Comments(null, 1)).Rating.UserId);
    }

    [Fact]
    public void PruneDropsGoneUsersAndGoneTitles()
    {
        // mario e luigi sul film, mario sulla stagione; luigi non c'è più, la stagione neanche.
        var book = new RatingBook();
        book.Set(_film, _mario, 8, null, T0);
        book.Set(_film, _luigi, 7, null, T0);
        book.Set(_season, _mario, 9, null, T0);
        Assert.Equal(2, book.Prune(user => user != _luigi, item => item != _season));
        Assert.Equal(_mario, Assert.Single(book.ForItem(_film)).UserId);
        Assert.Empty(book.ForItem(_season));
    }
}
