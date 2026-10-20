using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RatingServiceTests : IDisposable
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 20, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(T0);
    private readonly FriendService _friends;
    private readonly RecordingLogger<RatingService> _log = new();
    private readonly RatingService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly UserRef _toad;
    private readonly UserRef _daisy;
    private readonly RatedTitle _film;
    private readonly RatedTitle _season;

    public RatingServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _service = TestRatings.Create(_server, _folder, _time, _friends, _log);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _toad = _server.AddUser("Toad");
        _daisy = _server.AddUser("Daisy");
        foreach (var friend in new[] { _luigi, _peach, _daisy })
        {
            TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, friend.Id).GetAwaiter().GetResult();
        }

        _film = _server.AddRated("Il Padrino (1972)");
        _season = _server.AddRated("Breaking Bad · Stagione 2", isSeason: true);
    }

    public void Dispose() => _folder.Dispose();

    private static string N(Guid id) => id.ToString("N");

    private void DisableDaisy() => _server.Users[_daisy.Id] = _daisy with { Enabled = false };

    [Fact]
    public void FriendsOnlyNewestFirstWithoutDisabledAndMineApart()
    {
        _service.Save(_mario.Id, _film.Id, 7, null);
        _service.Save(_luigi.Id, _film.Id, 8, null);
        _time.Advance(TimeSpan.FromHours(1));
        _service.Save(_peach.Id, _film.Id, 6, "Lento");
        _service.Save(_toad.Id, _film.Id, 10, null);
        _service.Save(_daisy.Id, _film.Id, 1, null);
        DisableDaisy();

        var view = _service.ForItem(_mario.Id, N(_film.Id)).Value!;
        Assert.Equal(new[] { "Peach", "Luigi" }, view.Friends.Select(f => f.Name));
        Assert.Equal(new FriendRatingDto(N(_peach.Id), "Peach", 6, "Lento", T0.AddHours(1)), view.Friends[0]);
        Assert.Equal(7.0, view.Average);
        Assert.Equal(2, view.Count);
        Assert.Equal(new RatingScoreDto(7, null), view.Mine);
    }

    [Fact]
    public void AverageRoundsHalfUpToOneDecimal()
    {
        Assert.Equal(7.3, RatingService.Average([7, 7, 7, 8]));   // 7,25
        Assert.Equal(7.5, RatingService.Average([7, 8]));
        Assert.Equal(7.3, RatingService.Average([8, 7, 7]));      // 7,333…
        Assert.Equal(9.3, RatingService.Average([10, 9, 9]));     // 9,333…
        Assert.Null(RatingService.Average([]));
    }

    [Fact]
    public void WithoutFriendsVotesThereIsNoAverage()
    {
        _service.Save(_toad.Id, _film.Id, 9, null);

        var view = _service.ForItem(_mario.Id, N(_film.Id)).Value!;

        Assert.Empty(view.Friends);
        Assert.Null(view.Average);
        Assert.Equal(0, view.Count);
        Assert.Null(view.Mine);
        Assert.False(view.CanRate);
    }

    [Fact]
    public void CanRateWhenWatchedOrWithAnEarlierVote()
    {
        Assert.False(_service.ForItem(_mario.Id, N(_film.Id)).Value!.CanRate);
        Assert.False(_service.ForItem(_mario.Id, N(_season.Id)).Value!.CanRate);

        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        _server.WatchedTitles.Add((_mario.Id, _season.Id));
        Assert.True(_service.ForItem(_mario.Id, N(_film.Id)).Value!.CanRate);
        Assert.True(_service.ForItem(_mario.Id, N(_season.Id)).Value!.CanRate);

        _server.WatchedTitles.Clear();
        _service.Save(_mario.Id, _film.Id, 5, null);
        Assert.True(_service.ForItem(_mario.Id, N(_film.Id)).Value!.CanRate);
        Assert.False(_service.ForItem(_mario.Id, N(_season.Id)).Value!.CanRate);
    }

    [Fact]
    public void ATitleThatIsNotRatableOrNotVisibleIs400()
    {
        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        var vote = new RateRequest { Score = 7 };
        foreach (var id in new[] { "abc", N(Guid.NewGuid()), null })
        {
            Assert.Equal(HubStatus.Invalid, _service.ForItem(_mario.Id, id).Status);
            Assert.Equal(HubStatus.Invalid, _service.Rate(_mario.Id, id, vote));
        }

        _server.Unseen.Add((_mario.Id, _film.Id));
        Assert.Equal(HubStatus.Invalid, _service.ForItem(_mario.Id, N(_film.Id)).Status);
        Assert.Equal(HubStatus.Invalid, _service.Rate(_mario.Id, N(_film.Id), vote));

        _server.Unseen.Clear();
        _server.RatingLibraryFails = true;
        Assert.Equal(HubStatus.Invalid, _service.ForItem(_mario.Id, N(_film.Id)).Status);
        Assert.Equal(HubStatus.Invalid, _service.Rate(_mario.Id, N(_film.Id), vote));
        Assert.Contains(_log.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public void RateNeedsWatchedOrAnEarlierVote()
    {
        var vote = new RateRequest { Score = 7 };
        Assert.Equal(HubStatus.Invalid, _service.Rate(_mario.Id, N(_film.Id), vote));
        Assert.Empty(_service.Of(_film.Id, [_mario.Id]));

        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        Assert.Equal(HubStatus.Ok, _service.Rate(_mario.Id, N(_film.Id), vote));

        _server.WatchedTitles.Clear();
        Assert.Equal(HubStatus.Ok, _service.Rate(_mario.Id, N(_film.Id), new RateRequest { Score = 9 }));
        Assert.Equal(9, _service.Of(_film.Id, [_mario.Id])[_mario.Id].Score);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(11)]
    [InlineData(null)]
    public void ScoresOutsideOneToTenAreInvalid(int? score)
    {
        _server.WatchedTitles.Add((_mario.Id, _film.Id));

        Assert.Equal(HubStatus.Invalid, _service.Rate(_mario.Id, N(_film.Id), new RateRequest { Score = score }));
        Assert.Empty(_service.Of(_film.Id, [_mario.Id]));
    }

    [Fact]
    public void CommentsAreCleanedAndCountedInCodePoints()
    {
        Assert.Equal(HubStatus.Ok, _service.Save(_mario.Id, _film.Id, 7, "  Bello\n\tdavvero  "));
        Assert.Equal("Bello davvero", _service.Of(_film.Id, [_mario.Id])[_mario.Id].Comment);

        Assert.Equal(HubStatus.Ok, _service.Save(_mario.Id, _film.Id, 7, "   "));
        Assert.Null(_service.Of(_film.Id, [_mario.Id])[_mario.Id].Comment);

        Assert.Equal(HubStatus.Ok, _service.Save(_mario.Id, _film.Id, 7, string.Concat(Enumerable.Repeat("🎬", 200))));
        Assert.Equal(HubStatus.Invalid, _service.Save(_mario.Id, _film.Id, 7, new string('a', 201)));
    }

    [Fact]
    public void DeleteIs204EvenWithoutAVote()
    {
        Assert.Equal(HubStatus.Ok, _service.Delete(_mario.Id, N(_film.Id)));
        Assert.Equal(HubStatus.Ok, _service.Delete(_mario.Id, "abc"));

        _service.Save(_mario.Id, _film.Id, 7, null);
        Assert.Equal(HubStatus.Ok, _service.Delete(_mario.Id, N(_film.Id)));
        Assert.Null(_service.ForItem(_mario.Id, N(_film.Id)).Value!.Mine);
    }

    [Fact]
    public void TheSixtyFirstWriteInAnHourIsRateLimited()
    {
        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        var vote = new RateRequest { Score = 7 };
        for (var i = 0; i < 30; i++)
        {
            Assert.Equal(HubStatus.Ok, _service.Rate(_mario.Id, N(_film.Id), vote));
            Assert.Equal(HubStatus.Ok, _service.Delete(_mario.Id, N(_season.Id)));
            Assert.Equal(HubStatus.Ok, _service.Delete(_mario.Id, "abc")); // non conta
        }

        Assert.Equal(HubStatus.RateLimited, _service.Rate(_mario.Id, N(_film.Id), new RateRequest { Score = 3 }));
        Assert.Equal(7, _service.Of(_film.Id, [_mario.Id])[_mario.Id].Score);

        _time.Advance(TimeSpan.FromHours(1));
        Assert.Equal(HubStatus.Ok, _service.Rate(_mario.Id, N(_film.Id), new RateRequest { Score = 3 }));
    }

    [Fact]
    public void AdminCommentsComeInPagesOf50()
    {
        for (var i = 0; i < 51; i++)
        {
            var user = _server.AddUser("U" + i);
            _time.SetUtcNow(T0.AddMinutes(i));
            _service.Save(user.Id, _film.Id, 5, "c" + i);
        }

        _service.Save(_server.AddUser("Muto").Id, _film.Id, 5, null);

        var first = _service.Comments(null).Value!;
        Assert.Equal(50, first.Items.Count);
        Assert.Equal("c50", first.Items[0].Comment);
        Assert.Equal("U50", first.Items[0].UserName);
        Assert.Equal("Il Padrino (1972)", first.Items[0].Title);
        Assert.Equal(N(_film.Id), first.Items[0].ItemId);
        Assert.Equal(first.Items[49].UpdatedAt, first.Next);

        var second = _service.Comments(first.Next!.Value.ToString("O")).Value!;
        Assert.Single(second.Items);
        Assert.Null(second.Next);

        Assert.Equal(HubStatus.Invalid, _service.Comments("ieri").Status);

        _server.RatedTitles.Remove(_film.Id);
        Assert.Equal(string.Empty, _service.Comments(null).Value!.Items[0].Title);
    }

    [Fact]
    public void AdminDeleteRemovesOnlyTheComment()
    {
        _service.Save(_peach.Id, _film.Id, 6, "Lento");
        var before = _service.Of(_film.Id, [_peach.Id])[_peach.Id];
        _time.Advance(TimeSpan.FromHours(1));
        var admin = Guid.NewGuid();

        Assert.Equal(HubStatus.Ok, _service.DeleteComment(admin, N(_peach.Id), N(_film.Id)));

        var after = _service.Of(_film.Id, [_peach.Id])[_peach.Id];
        Assert.Equal(6, after.Score);
        Assert.Null(after.Comment);
        Assert.Equal(before.UpdatedAt, after.UpdatedAt);
        var infos = _log.Entries.Where(e => e.Level == LogLevel.Information && e.Message.Contains(N(_film.Id))).ToList();
        var entry = Assert.Single(infos);
        Assert.Contains(N(_peach.Id), entry.Message);
        Assert.DoesNotContain("Lento", entry.Message);

        Assert.Equal(HubStatus.Ok, _service.DeleteComment(admin, N(_peach.Id), N(_film.Id)));
        Assert.Single(_log.Entries, e => e.Level == LogLevel.Information && e.Message.Contains(N(_film.Id)));

        Assert.Equal(HubStatus.Invalid, _service.DeleteComment(admin, "x", N(_film.Id)));
    }

    [Fact]
    public void CleanupDropsGoneUsersAndGoneTitles()
    {
        _service.Save(_toad.Id, _film.Id, 5, null);
        _service.Save(_mario.Id, _film.Id, 7, null);
        _service.Save(_mario.Id, _season.Id, 8, null);
        _server.Users.Remove(_toad.Id);
        _server.RatedTitles.Remove(_season.Id);

        Assert.Equal(2, _service.Cleanup());

        var fresh = new RatingStore(_folder.RatingsFile, Microsoft.Extensions.Logging.Abstractions.NullLogger<RatingStore>.Instance).Load();
        Assert.Equal([_mario.Id], fresh.ForItem(_film.Id).Select(r => r.UserId));
        Assert.Empty(fresh.ForItem(_season.Id));
    }

    [Fact]
    public void CleanupKeepsVotesDuringAScanOrALibraryError()
    {
        _service.Save(_mario.Id, _film.Id, 7, null);
        _service.Save(_toad.Id, _season.Id, 7, null);
        _server.RatedTitles.Remove(_film.Id);

        _server.ScanRunning = true;
        Assert.Equal(0, _service.Cleanup());

        _server.ScanRunning = false;
        _server.RatingLibraryFails = true;
        Assert.Equal(0, _service.Cleanup());
        Assert.Single(_log.Entries, e => e.Level == LogLevel.Warning);

        _server.Users.Remove(_toad.Id);
        Assert.Equal(1, _service.Cleanup());
        Assert.Single(_service.Of(_film.Id, [_mario.Id]));
    }

    [Fact]
    public void ADiskErrorKeepsTheVoteInMemory()
    {
        Directory.CreateDirectory(_folder.RatingsFile);

        Assert.Equal(HubStatus.Ok, _service.Save(_mario.Id, _film.Id, 7, null));

        _server.WatchedTitles.Add((_mario.Id, _film.Id));
        Assert.Equal(7, _service.ForItem(_mario.Id, N(_film.Id)).Value!.Mine!.Score);
        Assert.Contains(_log.Entries, e => e.Level == LogLevel.Warning);
    }
}
