using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PresenceTrackerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;

    public PresenceTrackerTests()
    {
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public async Task ChangesCloseTogetherBecomeOneNotice()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        await _friends.AcceptAsync(_luigi.Id, _mario.Id);
        _server.Sent.Clear();

        _presence.Changed(_mario.Id);
        _time.Advance(TimeSpan.FromSeconds(1));
        _presence.Changed(_mario.Id);
        Assert.Empty(_server.Sent);

        _time.Advance(PresenceTracker.Delay);
        Assert.Single(_server.SentTo("s-luigi"));

        // Dopo l'avviso, un cambio nuovo ne prepara un altro.
        _presence.Changed(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, _server.SentTo("s-luigi").Count);
    }

    [Fact]
    public void WithoutFriendsNobodyIsNotified()
    {
        _presence.Changed(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.Sent);
    }
}
