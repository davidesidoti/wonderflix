using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class FriendServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero));
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly FriendService _friends;

    public FriendServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _friends = Service();
    }

    public void Dispose() => _folder.Dispose();

    private FriendService Service() => new(
        new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
        _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private async Task MakeFriends(UserRef a, UserRef b)
    {
        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(a.Id, b.Id));
        Assert.Equal(HubStatus.Ok, await _friends.AcceptAsync(b.Id, a.Id));
        _server.Sent.Clear();
    }

    [Fact]
    public async Task RequestNotifiesTheTargetWithTheName()
    {
        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(_mario.Id, _luigi.Id));

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("FriendRequest", json.GetProperty("Type").GetString());
        Assert.Equal(_mario.Id.ToString("N"), json.GetProperty("FromUserId").GetString());
        Assert.Equal("Mario", json.GetProperty("FromName").GetString());
        Assert.Empty(_server.SentTo("s-mario"));

        var luigi = _friends.GetFriends(_luigi.Id);
        Assert.Equal("Mario", Assert.Single(luigi.Incoming).Name);
        Assert.Equal("Luigi", Assert.Single(_friends.GetFriends(_mario.Id).Outgoing).Name);
    }

    [Fact]
    public async Task AcceptMakesFriendsNotifiesBothAndIsSaved()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Ok, await _friends.AcceptAsync(_luigi.Id, _mario.Id));

        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        // Un servizio nuovo rilegge il file.
        var reloaded = Service().GetFriends(_mario.Id);
        Assert.Equal("Luigi", Assert.Single(reloaded.Friends).Name);
    }

    [Fact]
    public async Task CrossedRequestBecomesFriendship()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(_luigi.Id, _mario.Id));

        Assert.Equal("Luigi", Assert.Single(_friends.GetFriends(_mario.Id).Friends).Name);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task RefusedRequests()
    {
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, Guid.NewGuid()));
        var disabled = _server.AddUser("Bowser", enabled: false);
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, disabled.Id));
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, _mario.Id));
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, _luigi.Id));
    }

    [Fact]
    public async Task RequestsAreRateLimited()
    {
        for (var i = 0; i < 20; i++)
        {
            await _friends.RequestAsync(_mario.Id, Guid.NewGuid());
        }

        Assert.Equal(HubStatus.RateLimited, await _friends.RequestAsync(_mario.Id, _luigi.Id));
    }

    [Fact]
    public async Task AcceptOrDeclineWithoutRequestIsForbidden()
    {
        Assert.Equal(HubStatus.Forbidden, await _friends.AcceptAsync(_luigi.Id, _mario.Id));
        Assert.Equal(HubStatus.Forbidden, await _friends.DeclineAsync(_luigi.Id, _mario.Id));
    }

    [Fact]
    public async Task DeclineCancelAndRemoveNotifyBoth()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();
        Assert.Equal(HubStatus.Ok, await _friends.DeclineAsync(_luigi.Id, _mario.Id));
        Assert.Empty(_friends.GetFriends(_mario.Id).Outgoing);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));

        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();
        Assert.Equal(HubStatus.Ok, await _friends.CancelAsync(_mario.Id, _luigi.Id));
        Assert.Empty(_friends.GetFriends(_luigi.Id).Incoming);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        // Annullare una richiesta che non c'è non è un errore.
        Assert.Equal(HubStatus.Ok, await _friends.CancelAsync(_mario.Id, _luigi.Id));

        await MakeFriends(_mario, _luigi);
        Assert.Equal(HubStatus.Ok, await _friends.RemoveAsync(_luigi.Id, _mario.Id));
        Assert.Empty(_friends.GetFriends(_mario.Id).Friends);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
    }

    [Fact]
    public async Task FriendsAreSortedWithOnlineStateAndWithoutDeletedUsers()
    {
        await MakeFriends(_mario, _peach);
        await MakeFriends(_mario, _luigi);
        var daisy = _server.AddUser("Daisy");
        await MakeFriends(_mario, daisy);
        _server.Users.Remove(daisy.Id);

        var friends = _friends.GetFriends(_mario.Id).Friends;

        Assert.Equal(new[] { "Luigi", "Peach" }, friends.Select(f => f.Name));
        Assert.True(friends[0].Online);
        Assert.False(friends[1].Online);
        Assert.All(friends, f => Assert.Null(f.Party));
    }

    [Fact]
    public async Task SearchFindsNamesContainingTheText()
    {
        await MakeFriends(_mario, _luigi);
        await _friends.RequestAsync(_peach.Id, _mario.Id);
        _server.AddUser("Luisa", enabled: false);
        _server.AddUser("Waluigi");

        Assert.Empty(_friends.Search(_mario.Id, "l").Value!);
        Assert.Empty(_friends.Search(_mario.Id, "  ").Value!);

        var results = _friends.Search(_mario.Id, " LUI ").Value!;
        Assert.Equal(new[] { "Luigi", "Waluigi" }, results.Select(r => r.Name));
        Assert.Equal(new[] { FriendRelations.Friend, FriendRelations.None }, results.Select(r => r.Relation));
        Assert.Equal(FriendRelations.Incoming, Assert.Single(_friends.Search(_mario.Id, "pea").Value!).Relation);
        Assert.Equal(FriendRelations.Outgoing, Assert.Single(_friends.Search(_peach.Id, "mar").Value!).Relation);
        Assert.Empty(_friends.Search(_mario.Id, "mario").Value!);
    }

    [Fact]
    public void SearchReturnsAtMostTenAndIsRateLimited()
    {
        for (var i = 0; i < 12; i++)
        {
            _server.AddUser($"Toad {i:00}");
        }

        Assert.Equal(FriendService.MaxSearchResults, _friends.Search(_mario.Id, "toad").Value!.Count);
        for (var i = 1; i < 30; i++)
        {
            Assert.Equal(HubStatus.Ok, _friends.Search(_mario.Id, "toad").Status);
        }

        Assert.Equal(HubStatus.RateLimited, _friends.Search(_mario.Id, "toad").Status);
    }

    [Fact]
    public async Task NotifyFriendsReachesOnlyOnlineFriends()
    {
        await MakeFriends(_mario, _luigi);
        await MakeFriends(_mario, _peach);

        await _friends.NotifyFriendsAsync(_mario.Id);

        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-mario"));
    }
}
