using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly InboxService _inbox;
    private readonly RecommendationService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly RecommendableItem _dune;

    public RecommendationServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _inbox = TestInbox.Create(_server, _folder, _time);
        _service = TestRecommendations.Create(_server, _folder, _time, _friends, _inbox);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _dune = _server.AddRecommendable("Dune", 2021);
        TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id).GetAwaiter().GetResult();
        TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id).GetAwaiter().GetResult();
        TestRecommendations.MakeFriendsAsync(_friends, _peach.Id, _luigi.Id).GetAwaiter().GetResult();
    }

    public void Dispose() => _folder.Dispose();

    private static string N(Guid id) => id.ToString("N");

    private Task<HubResult<RecommendResponse>> Recommend(
        UserRef from, RecommendableItem item, string? message, params UserRef[] to) =>
        _service.RecommendAsync(
            from.Id, new RecommendRequest { ItemId = N(item.Id), To = to.Select(u => (string?)N(u.Id)).ToList(), Message = message });

    [Fact]
    public async Task TargetsAreActiveFriendsByNameWithOnlineAndAccess()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        await TestRecommendations.MakeFriendsAsync(_friends, bowser.Id, _mario.Id);
        _server.AddSession("s-peach", _peach);
        _server.Unseen.Add((_luigi.Id, _dune.Id));

        var result = _service.Targets(_mario.Id, N(_dune.Id));

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(
            new[] { ("Luigi", false, false), ("Peach", true, true) },
            result.Value!.Friends.Select(f => (f.Name, f.Online, f.CanSee)));
        Assert.Equal(N(_luigi.Id), result.Value.Friends[0].UserId);
    }

    [Fact]
    public void TargetsNeedATitleTheCallerCanSee()
    {
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, null).Status);
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, "non-un-id").Status);
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, N(Guid.NewGuid())).Status);
        _server.Unseen.Add((_mario.Id, _dune.Id));
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, N(_dune.Id)).Status);
    }

    [Fact]
    public async Task ARecommendationReachesTheListAndTheInbox()
    {
        var result = await Recommend(_mario, _dune, "da vedere", _luigi, _peach);

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(2, result.Value!.Sent);
        var item = Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Equal(N(_dune.Id), item.ItemId);
        var from = Assert.Single(item.From);
        Assert.Equal((N(_mario.Id), "Mario", "da vedere", _time.GetUtcNow()), (from.UserId, from.Name, from.Message, from.CreatedAt));
        var entry = Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(InboxEntryTypes.Recommendation, entry.Type);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Empty(_service.List(_mario.Id).Items);
    }

    [Fact]
    public async Task InvalidRecipientsAreSkippedSilently()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        await TestRecommendations.MakeFriendsAsync(_friends, bowser.Id, _mario.Id);
        var toad = _server.AddUser("Toad"); // non amico
        _server.Unseen.Add((_peach.Id, _dune.Id));

        var result = await _service.RecommendAsync(_mario.Id, new RecommendRequest
        {
            ItemId = N(_dune.Id),
            To = ["non-un-id", null, N(_mario.Id), N(_luigi.Id), N(_luigi.Id), N(toad.Id), N(bowser.Id), N(_peach.Id), N(Guid.NewGuid())],
        });

        Assert.Equal(1, result.Value!.Sent);
        Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Empty(_service.List(_peach.Id).Items);
        Assert.Empty(_inbox.Get(toad.Id).Entries);

        // Nessuno valido: riuscito, ma non arriva a nessuno.
        Assert.Equal(0, (await Recommend(_mario, _dune, null, toad)).Value!.Sent);
    }

    [Fact]
    public async Task BadRequestsAreInvalid()
    {
        var episode = new RecommendableItem(Guid.NewGuid(), "Pilot", null); // non in Recommendables: non è un film né una serie
        Assert.Equal(HubStatus.Invalid, (await _service.RecommendAsync(_mario.Id, null)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, episode, null, _luigi)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, null)).Status);
        Assert.Equal(
            HubStatus.Invalid,
            (await _service.RecommendAsync(_mario.Id, new RecommendRequest { ItemId = N(_dune.Id), To = null })).Status);
        Assert.Equal(
            HubStatus.Invalid,
            (await _service.RecommendAsync(_mario.Id, new RecommendRequest
            {
                ItemId = N(_dune.Id),
                To = Enumerable.Range(0, RecommendationService.MaxRecipients + 1).Select(_ => (string?)N(_luigi.Id)).ToList(),
            })).Status);

        _server.Unseen.Add((_mario.Id, _dune.Id));
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, null, _luigi)).Status);
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task MessagesAreCleanedAndCountedInCodePoints()
    {
        await Recommend(_mario, _dune, "  \n \r\n ", _luigi);
        Assert.Null(Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        await Recommend(_mario, _dune, " da vedere\r\n\r\nstasera ", _luigi);
        Assert.Equal("da vedere stasera", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        await Recommend(_mario, _dune, "a\tb", _luigi);
        Assert.Equal("a b", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        await Recommend(_mario, _dune, "a\x2028" + "b", _luigi);
        Assert.Equal("a b", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        Assert.Equal(HubStatus.Ok, (await Recommend(_mario, _dune, string.Concat(Enumerable.Repeat("😂", 200)), _luigi)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, new string('a', 201), _luigi)).Status);
    }

    [Fact]
    public async Task TooManyRecipientsInAnHourAreRateLimitedAndNothingIsSaved()
    {
        var friends = Enumerable.Range(0, 31).Select(i => _server.AddUser($"Amico {i}")).ToList();
        foreach (var friend in friends)
        {
            // Chiede l'amico: Mario ha un limite di 20 richieste all'ora.
            await TestRecommendations.MakeFriendsAsync(_friends, friend.Id, _mario.Id);
        }

        Assert.Equal(30, (await Recommend(_mario, _dune, null, friends.Take(30).ToArray())).Value!.Sent);
        var other = _server.AddRecommendable("The Bear");

        Assert.Equal(HubStatus.RateLimited, (await Recommend(_mario, other, null, friends[30])).Status);

        Assert.Empty(_service.List(friends[30].Id).Items);
        Assert.Empty(_inbox.Get(friends[30].Id).Entries);
    }

    [Fact]
    public async Task TwoFriendsGiveOneTitleWithBothSenders()
    {
        await Recommend(_mario, _dune, "da vedere", _luigi);
        _time.Advance(TimeSpan.FromMinutes(1));
        await Recommend(_peach, _dune, null, _luigi);

        var item = Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Equal(new[] { "Peach", "Mario" }, item.From.Select(f => f.Name));
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task TitlesOlderThan60DaysLeave()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _time.Advance(RecommendationService.MaxAge);
        Assert.Single(_service.List(_luigi.Id).Items);

        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task TitlesTheRecipientCanNoLongerSeeLeave()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _server.Unseen.Add((_luigi.Id, _dune.Id));

        Assert.Empty(_service.List(_luigi.Id).Items);

        // Tolto per sempre: anche con l'accesso di nuovo non torna.
        _server.Unseen.Clear();
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task WatchedTitlesLeaveAndComeBackWhenRecommendedAgain()
    {
        // Visto prima del consiglio: resta.
        _server.Watched[(_luigi.Id, _dune.Id)] = _time.GetUtcNow().AddDays(-3);
        await Recommend(_mario, _dune, null, _luigi);
        Assert.Single(_service.List(_luigi.Id).Items);

        // Visto dopo: esce.
        _time.Advance(TimeSpan.FromHours(2));
        _server.Watched[(_luigi.Id, _dune.Id)] = _time.GetUtcNow();
        Assert.Empty(_service.List(_luigi.Id).Items);

        // Riconsigliato dopo la visione: torna.
        _time.Advance(TimeSpan.FromHours(1));
        await Recommend(_peach, _dune, "di nuovo!", _luigi);
        Assert.Equal("Peach", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Name);
    }

    [Fact]
    public async Task AnUnfriendedSenderLeavesTheOthersStay()
    {
        await Recommend(_mario, _dune, null, _luigi);
        await Recommend(_peach, _dune, null, _luigi);
        await _friends.RemoveAsync(_luigi.Id, _mario.Id);

        Assert.Equal("Peach", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Name);

        await _friends.RemoveAsync(_luigi.Id, _peach.Id);
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task ALibraryErrorKeepsTheTitleAndTheAnswer()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _server.LibraryFails = true;

        Assert.Single(_service.List(_luigi.Id).Items);

        _server.LibraryFails = false;
        Assert.Single(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task NotInterestedRemovesTheTitleOnly()
    {
        var bear = _server.AddRecommendable("The Bear");
        await Recommend(_mario, _dune, null, _luigi);
        await Recommend(_mario, bear, null, _luigi);

        _service.Dismiss(_luigi.Id, N(_dune.Id));
        _service.Dismiss(_luigi.Id, "non-un-id");
        _service.Dismiss(_luigi.Id, null);

        Assert.Equal(N(bear.Id), Assert.Single(_service.List(_luigi.Id).Items).ItemId);
        // La voce della cassetta resta (spec N §6.4).
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task CleanupDropsOldTitlesLostSendersAndMissingUsersAndSaves()
    {
        await Recommend(_mario, _dune, null, _luigi, _peach);
        await _friends.RemoveAsync(_peach.Id, _mario.Id);
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(2, _service.Cleanup());

        var saved = new RecommendationStore(
            _folder.RecommendationsFile, Microsoft.Extensions.Logging.Abstractions.NullLogger<RecommendationStore>.Instance).Load();
        Assert.Empty(saved.List(_luigi.Id));
        Assert.Empty(saved.List(_peach.Id));
        Assert.Equal(0, _service.Cleanup());
    }

    [Fact]
    public async Task RecommendationsSurviveARestart()
    {
        await Recommend(_mario, _dune, "da vedere", _luigi);

        var restarted = TestRecommendations.Create(_server, _folder, _time, _friends, _inbox);

        Assert.Equal("da vedere", Assert.Single(Assert.Single(restarted.List(_luigi.Id).Items).From).Message);
    }
}
