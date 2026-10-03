using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PartyAnnouncerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FriendService _friends;
    private readonly PartyDirectory _parties;
    private readonly PartyAnnouncer _announcer;
    private readonly PartyService _service;
    private readonly Guid _group = Guid.NewGuid();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly CallerSession _marioSession;

    public PartyAnnouncerTests()
    {
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _parties = new PartyDirectory(_time);
        _announcer = new PartyAnnouncer(
            _parties, _server, _server, _friends, _server, _time, NullLogger<PartyAnnouncer>.Instance);
        _service = new PartyService(
            _parties, _server, _server, _server, _friends, new PartyRegistry(), _announcer, _server,
            new RateLimiter(_time), NullLogger<PartyService>.Instance);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _marioSession = _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _server.AddSession("s-peach", _peach);
        _server.Groups[_group] = ["Mario"];
        _server.GroupNames[_group] = "Mario · Dune";
    }

    public void Dispose()
    {
        _announcer.Dispose();
        _folder.Dispose();
    }

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private async Task MakeFriends(UserRef a, UserRef b)
    {
        await _friends.RequestAsync(a.Id, b.Id);
        await _friends.AcceptAsync(b.Id, a.Id);
        _server.Sent.Clear();
    }

    /// <summary>L'app ha mandato la coda: il gruppo esce da Idle.</summary>
    private void QueueSet() => _server.GroupStates[_group] = "Waiting";

    [Fact]
    public void TheAnnouncementWaitsForTheQueue()
    {
        Assert.Equal(HubStatus.Ok, _service.Register(_marioSession, _group, PartyModes.Public).Status);
        Assert.Empty(_server.Sent);

        // Senza coda il gruppo lo vedrebbe chiunque: si aspetta ancora.
        _time.Advance(PartyAnnouncer.Delay);
        Assert.Empty(_server.Sent);

        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);
        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("PartyStarted", json.GetProperty("Type").GetString());
        Assert.Equal(_group.ToString("N"), json.GetProperty("GroupId").GetString());
        Assert.Equal("Mario · Dune", json.GetProperty("Name").GetString());
        Assert.Equal("Public", json.GetProperty("Mode").GetString());
        Assert.Single(_server.SentTo("s-peach"));
        Assert.Empty(_server.SentTo("s-mario"));
        Assert.All(_server.SentTokens, token => Assert.Equal(CancellationToken.None, token));

        // Un avviso solo.
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Equal(2, _server.Sent.Count);
    }

    [Fact]
    public void TheAnnouncementKeepsWaitingUntilItGivesUp()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _time.Advance(PartyAnnouncer.GiveUpAfter - PartyAnnouncer.Delay);
        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);
        Assert.Equal(2, _server.Sent.Count);
    }

    [Fact]
    public void AnAnnouncementStillIdleAfterGiveUpAfterIsDropped()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        QueueSet();
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public void SessionsThatCannotSeeTheGroupAreSkipped()
    {
        // Peach non ha accesso alla libreria del titolo in coda.
        _server.Hidden.Add(("s-peach", _group));
        _service.Register(_marioSession, _group, PartyModes.Public);
        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);

        Assert.Single(_server.SentTo("s-luigi"));
        Assert.Empty(_server.SentTo("s-peach"));
    }

    [Fact]
    public void AFailingSessionDoesNotStopTheOthers()
    {
        _server.Failing.Add("s-luigi");
        _service.Register(_marioSession, _group, PartyModes.Public);
        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);

        Assert.Single(_server.SentTo("s-peach"));
    }

    [Fact]
    public void NothingIsSentIfTheGroupEndsBeforeTheTick()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _server.Groups.Remove(_group);
        _time.Advance(PartyAnnouncer.Delay);

        // Anche se un gruppo con lo stesso id tornasse, l'avviso non c'è più.
        _server.Groups[_group] = ["Mario"];
        QueueSet();
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public void NothingIsSentIfCleanupForgetsThePartyBeforeTheTick()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _server.Groups.Remove(_group);
        Assert.Equal(1, _service.Cleanup());
        _server.Groups[_group] = ["Mario"];
        QueueSet();

        _time.Advance(PartyAnnouncer.Delay);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task FriendsModeUsesTheFriendsAtFireTime()
    {
        await MakeFriends(_mario, _peach);
        _service.Register(_marioSession, _group, PartyModes.Friends);

        // Prima dell'avviso Peach non è più amica e Luigi lo diventa.
        await _friends.RemoveAsync(_mario.Id, _peach.Id);
        await MakeFriends(_mario, _luigi);
        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);

        Assert.Equal(new[] { "PartyStarted" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-peach"));
        Assert.Empty(_server.SentTo("s-mario"));
    }

    [Fact]
    public void ParticipantsAreSkipped()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        _server.Groups[_group] = ["Mario", "Luigi"];
        QueueSet();
        _time.Advance(PartyAnnouncer.Delay);

        Assert.Empty(_server.SentTo("s-luigi"));
        Assert.Single(_server.SentTo("s-peach"));
    }

    [Fact]
    public void PrivatePartiesAreNotAnnounced()
    {
        _service.Register(_marioSession, _group, PartyModes.Private);
        QueueSet();
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public void DisposeCancelsPendingAnnouncements()
    {
        _service.Register(_marioSession, _group, PartyModes.Public);
        QueueSet();
        _announcer.Dispose();
        _time.Advance(PartyAnnouncer.GiveUpAfter);
        Assert.Empty(_server.Sent);
    }
}
