using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityReadTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly PartyRegistry _registry = new();
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _luigiSession;

    public ActivityReadTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _service = TestActivity.Create(_server, _folder, _time, _friends, _presence, _registry);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _luigiSession = _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private Task FriendsAsync(UserRef a, UserRef b) => TestRecommendations.MakeFriendsAsync(_friends, a.Id, b.Id);

    private FriendEntry Luigi() =>
        _friends.GetFriends(_mario.Id, nowPlayingOf: f => _service.NowPlayingFor(_mario.Id, f)).Friends.Single(f => f.Name == "Luigi");

    [Fact]
    public async Task AFriendWatchingAMovieShowsIt()
    {
        await FriendsAsync(_mario, _luigi);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune));

        var entry = Luigi();

        Assert.True(entry.Online);
        Assert.Equal(new FriendNowPlaying(dune.ToString("N"), "Dune", null, null, null, null), entry.NowPlaying);
    }

    [Fact]
    public async Task AnEpisodeCarriesSeriesSeasonAndNumber()
    {
        await FriendsAsync(_mario, _luigi);
        var episode = Guid.NewGuid();
        var series = Guid.NewGuid();
        _server.Playback.Add(new AppPlayback(
            "s-luigi", _luigi.Id, new PlayingTitle(episode, "Pilot", series, series, "The Bear", 2, 3), 0, default));

        Assert.Equal(
            new FriendNowPlaying(episode.ToString("N"), "Pilot", series.ToString("N"), "The Bear", 2, 3),
            Luigi().NowPlaying);
    }

    [Fact]
    public async Task NothingIsShownWithoutSharingAccessOrInAParty()
    {
        await FriendsAsync(_mario, _luigi);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune));

        _service.SetShare(_luigi.Id, false);
        Assert.Null(Luigi().NowPlaying);
        _service.SetShare(_luigi.Id, true);

        _server.Unseen.Add((_mario.Id, dune));
        Assert.Null(Luigi().NowPlaying);
        Assert.True(Luigi().Online);
        _server.Unseen.Clear();

        // In un party che Mario non vede (nessun Party nella voce): niente "Sta guardando".
        _registry.Register(Guid.NewGuid(), "s-luigi", "Luigi");
        var entry = Luigi();
        Assert.Null(entry.Party);
        Assert.Null(entry.NowPlaying);
    }

    [Fact]
    public async Task TheMostRecentSessionWins()
    {
        await FriendsAsync(_mario, _luigi);
        var other = _server.AddSession("s-luigi-2", _luigi);
        var old = Guid.NewGuid();
        var recent = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, recent, "Recente", checkIn: _time.GetUtcNow()));
        _server.Playback.Add(TestActivity.Movie(other, old, "Vecchio", checkIn: _time.GetUtcNow().AddMinutes(-1)));

        Assert.Equal(recent.ToString("N"), Luigi().NowPlaying!.ItemId);
    }

    [Fact]
    public async Task APlaybackErrorLeavesOnlyOnline()
    {
        await FriendsAsync(_mario, _luigi);
        _server.Playback.Add(TestActivity.Movie(_luigiSession, Guid.NewGuid()));
        _server.PlaybackFails = true;

        var entry = Luigi();

        Assert.True(entry.Online);
        Assert.Null(entry.NowPlaying);
    }

    [Fact]
    public async Task OfflineFriendsAndFriendsInAVisiblePartyAreNotAsked()
    {
        var peach = _server.AddUser("Peach");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, peach);
        var asked = new List<Guid>();
        var party = new FriendParty(Guid.NewGuid().ToString("N"), "Dune");

        var response = _friends.GetFriends(
            _mario.Id,
            partyOf: f => party,
            nowPlayingOf: f =>
            {
                asked.Add(f);
                return null;
            });

        Assert.Empty(asked);
        Assert.Equal(party, response.Friends.Single(f => f.Name == "Luigi").Party);
    }

    [Fact]
    public async Task ThePositionIsTheFriendsCurrentOne()
    {
        var dune = Guid.NewGuid();
        var luigiId = _luigi.Id.ToString("N");

        // Non amici: 409 anche se Luigi guarda.
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune, position: TimeSpan.FromMinutes(42)));
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);

        await FriendsAsync(_mario, _luigi);
        var result = _service.Position(_mario.Id, luigiId);
        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(new FriendPosition(dune.ToString("N"), TimeSpan.FromMinutes(42).Ticks), result.Value);

        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, "x").Status);
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, null).Status);

        _server.Unseen.Add((_mario.Id, dune));
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);
        _server.Unseen.Clear();

        _server.Playback.Clear();
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);
    }

    [Fact]
    public async Task FriendsWatchedGroupsTitlesNewestFirst()
    {
        var peach = _server.AddUser("Peach");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, peach);
        var peachSession = new CallerSession("s-peach", peach.Id, "Peach");
        var dune = Guid.NewGuid();
        var bear = Guid.NewGuid();
        var start = _time.GetUtcNow();

        _service.Report(TestActivity.Report(_luigiSession, dune, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(TimeSpan.FromMinutes(30));
        _service.Report(TestActivity.Report(_luigiSession, bear, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(TimeSpan.FromMinutes(30));
        _service.Report(TestActivity.Report(peachSession, dune, TimeSpan.FromMinutes(6)), stopped: false);

        var items = _service.FriendsWatched(_mario.Id).Items;

        Assert.Equal(new[] { dune.ToString("N"), bear.ToString("N") }, items.Select(i => i.ItemId));
        Assert.Equal(
            new[]
            {
                new FriendWatcher(peach.Id.ToString("N"), "Peach", start.AddHours(1)),
                new FriendWatcher(_luigi.Id.ToString("N"), "Luigi", start),
            },
            items[0].By);
        Assert.Equal(new[] { new FriendWatcher(_luigi.Id.ToString("N"), "Luigi", start.AddMinutes(30)) }, items[1].By);
    }

    [Fact]
    public async Task FriendsWatchedSkipsWhatTheViewerSawCannotSeeOrIsOldOrNotFromFriends()
    {
        var peach = _server.AddUser("Peach");
        var toad = _server.AddUser("Toad");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, toad);
        var old = Guid.NewGuid();
        var seen = Guid.NewGuid();
        var hidden = Guid.NewGuid();
        var stranger = Guid.NewGuid();
        var disabled = Guid.NewGuid();
        var kept = Guid.NewGuid();

        _service.Report(TestActivity.Report(_luigiSession, old, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(ActivityService.MaxAge + TimeSpan.FromMinutes(1));
        _service.Report(TestActivity.Report(_luigiSession, seen, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(_luigiSession, hidden, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(_luigiSession, kept, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(new CallerSession("s-peach", peach.Id, "Peach"), stranger, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(new CallerSession("s-toad", toad.Id, "Toad"), disabled, TimeSpan.FromMinutes(6)), stopped: false);
        _server.Watched[(_mario.Id, seen)] = _time.GetUtcNow().AddYears(-1);
        _server.Unseen.Add((_mario.Id, hidden));
        _server.Users[toad.Id] = toad with { Enabled = false };

        var items = _service.FriendsWatched(_mario.Id).Items;

        Assert.Equal(new[] { kept.ToString("N") }, items.Select(i => i.ItemId));
    }

    [Fact]
    public async Task FriendsWatchedStopsAtThirty()
    {
        await FriendsAsync(_mario, _luigi);
        for (var i = 0; i < 35; i++)
        {
            _service.Report(TestActivity.Report(_luigiSession, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
            _time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(ActivityService.MaxFriendsWatched, _service.FriendsWatched(_mario.Id).Items.Count);
    }

    [Fact]
    public async Task ALibraryErrorSkipsTheTitle()
    {
        await FriendsAsync(_mario, _luigi);
        _service.Report(TestActivity.Report(_luigiSession, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
        _server.LibraryFails = true;

        Assert.Empty(_service.FriendsWatched(_mario.Id).Items);
    }

    [Fact]
    public void NowPlayingIsLeftOutWhenMissing()
    {
        var plain = JsonSerializer.Serialize(new FriendEntry("u", "Luigi", true, null));
        Assert.DoesNotContain("NowPlaying", plain, StringComparison.Ordinal);
        Assert.Contains("\"Party\":null", plain, StringComparison.Ordinal);

        var movie = JsonSerializer.Serialize(new FriendEntry("u", "Luigi", true, null, new FriendNowPlaying("i", "Dune", null, null, null, null)));
        Assert.Contains("\"NowPlaying\":{\"ItemId\":\"i\",\"Title\":\"Dune\"}", movie, StringComparison.Ordinal);
    }
}
