using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class DownloadBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 28, 12, 0, 0, TimeSpan.Zero);

    private const string NeedsYouReason = "NothingFound";

    private static DownloadChoice Choice(string key, DateTimeOffset at) => new() { Key = key, At = at, Title = key };

    [Fact]
    public void ChoicesOlderThanNinetyDaysArePruned()
    {
        var book = new DownloadBook();
        book.AddChoice(Choice("movie:1", Now - DownloadBook.ChoiceRetention - TimeSpan.FromMinutes(1)));
        book.AddChoice(Choice("movie:2", Now - DownloadBook.ChoiceRetention));
        book.AddChoice(Choice("movie:3", Now));

        Assert.Equal(1, book.Prune(Now));

        Assert.Equal(["movie:3", "movie:2"], book.Choices.Select(c => c.Key));
    }

    [Fact]
    public void ChoicesComeNewestFirst()
    {
        var book = new DownloadBook();
        book.AddChoice(Choice("movie:1", Now - TimeSpan.FromDays(2)));
        book.AddChoice(Choice("movie:2", Now));
        book.AddChoice(Choice("movie:3", Now - TimeSpan.FromDays(1)));

        Assert.Equal(["movie:2", "movie:3", "movie:1"], book.Choices.Select(c => c.Key));
    }

    [Fact]
    public void AcceptingRemovesFromReview()
    {
        var book = new DownloadBook();
        book.SetReview([new ReviewItem { Key = "movie:1" }, new ReviewItem { Key = "movie:2" }], Now);

        Assert.True(book.Accept("movie:1"));

        Assert.Equal(["movie:2"], book.Review.Select(r => r.Key));
        Assert.True(book.IsAccepted("movie:1"));
        Assert.False(book.IsAccepted("movie:2"));
        Assert.False(book.Accept("movie:1"));
    }

    [Fact]
    public void PutReplacesByKey()
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry { Key = "movie:1", State = "Waiting" });
        book.Put(new DownloadEntry { Key = "movie:1", State = "Downloading" });

        Assert.Single(book.Entries);
        Assert.Equal("Downloading", book.Get("movie:1")!.State);
        Assert.True(book.Remove("movie:1"));
        Assert.False(book.Remove("movie:1"));
        Assert.Null(book.Get("movie:1"));
    }

    [Fact]
    public void ARoundTripKeepsEverything()
    {
        var book = new DownloadBook();
        book.Put(new DownloadEntry
        {
            Key = "season:5:2",
            Kind = "Season",
            Title = "Serie",
            PosterUrl = "https://poster",
            State = "NeedsYou",
            Reason = NeedsYouReason,
            AvailableSince = Now,
            LastSearchAt = Now,
            NextSearchAt = Now + TimeSpan.FromHours(6),
            UpgradeUntil = Now + TimeSpan.FromDays(30),
            QueueId = 7,
            LastSizeLeft = 123,
            LastProgressAt = Now,
            CurrentScore = 80,
            CurrentQualityId = 9,
            ManualImportPending = true,
            ProfileId = 4,
            RuntimeMinutes = 45,
        });
        book.AddChoice(new DownloadChoice
        {
            Guid = "g",
            IndexerId = 3,
            Indexer = "idx",
            ReleaseTitle = "rel",
            Quality = "WEBRip-1080p",
            QualityId = 15,
            Resolution = 1080,
            SizeBytes = 5_000_000_000,
            Score = 120,
            Seeders = 12,
            Key = "movie:1",
            Kind = "Movie",
            Title = "Film",
            PosterUrl = "p",
            At = Now,
            PreviousSizeBytes = 1,
            PreviousScore = 2,
            ByAdmin = true,
        });
        book.SetReview([new ReviewItem { Key = "movie:2", Kind = "Movie", Title = "T", PosterUrl = "p", Score = 5, SizeBytes = 6, Quality = "q" }], Now);
        book.Accept("movie:3");

        var copy = DownloadBook.FromFile(book.ToFile());

        Assert.Equivalent(book.Entries, copy.Entries);
        Assert.Equivalent(book.Choices, copy.Choices);
        Assert.Equivalent(book.Review, copy.Review);
        Assert.Equal(Now, copy.ReviewAt);
        Assert.True(copy.IsAccepted("movie:3"));
        Assert.Equal(NeedsYouReason, copy.Get("season:5:2")!.Reason);
    }
}
