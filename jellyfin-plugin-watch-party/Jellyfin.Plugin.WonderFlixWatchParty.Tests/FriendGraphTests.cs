using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class FriendGraphTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly FriendGraph _graph = new();

    [Fact]
    public void RequestThenAcceptMakesFriendsBothWays()
    {
        Assert.Equal(FriendRequestOutcome.Sent, _graph.Request(_mario, _luigi, Now));
        Assert.Equal(_mario, Assert.Single(_graph.IncomingOf(_luigi)).From);
        Assert.Equal(_luigi, Assert.Single(_graph.OutgoingOf(_mario)).To);

        Assert.Equal(FriendChange.Done, _graph.Accept(_luigi, _mario));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.True(_graph.AreFriends(_luigi, _mario));
        Assert.Equal(new[] { _luigi }, _graph.FriendsOf(_mario));
        Assert.Equal(new[] { _mario }, _graph.FriendsOf(_luigi));
        Assert.Empty(_graph.IncomingOf(_luigi));
        Assert.Empty(_graph.OutgoingOf(_mario));
    }

    [Fact]
    public void CrossedRequestsBecomeFriends()
    {
        _graph.Request(_mario, _luigi, Now);
        Assert.Equal(FriendRequestOutcome.BecameFriends, _graph.Request(_luigi, _mario, Now));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.Empty(_graph.IncomingOf(_mario));
        Assert.Empty(_graph.IncomingOf(_luigi));
    }

    [Fact]
    public void RejectsSelfDuplicatesAndFriends()
    {
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _mario, Now));
        _graph.Request(_mario, _luigi, Now);
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
        _graph.Accept(_luigi, _mario);
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_luigi, _mario, Now));
    }

    [Fact]
    public void AcceptWithoutRequestIsMissing()
    {
        Assert.Equal(FriendChange.Missing, _graph.Accept(_luigi, _mario));
        Assert.False(_graph.AreFriends(_mario, _luigi));
    }

    [Fact]
    public void DeclineCancelAndRemove()
    {
        _graph.Request(_mario, _luigi, Now);
        Assert.True(_graph.Decline(_luigi, _mario));
        Assert.False(_graph.Decline(_luigi, _mario));
        Assert.Empty(_graph.OutgoingOf(_mario));

        _graph.Request(_mario, _peach, Now);
        Assert.True(_graph.Cancel(_mario, _peach));
        Assert.Empty(_graph.IncomingOf(_peach));

        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        Assert.True(_graph.Remove(_luigi, _mario));
        Assert.False(_graph.AreFriends(_mario, _luigi));
        Assert.False(_graph.Remove(_luigi, _mario));
    }

    [Fact]
    public void OutgoingRequestsAreLimited()
    {
        for (var i = 0; i < FriendGraph.MaxOutgoing; i++)
        {
            Assert.Equal(FriendRequestOutcome.Sent, _graph.Request(_mario, Guid.NewGuid(), Now));
        }

        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
    }

    [Fact]
    public void FriendsAreLimited()
    {
        for (var i = 0; i < FriendGraph.MaxFriends; i++)
        {
            var other = Guid.NewGuid();
            _graph.Request(other, _mario, Now);
            Assert.Equal(FriendChange.Done, _graph.Accept(_mario, other));
        }

        _graph.Request(_luigi, _mario, Now);
        Assert.Equal(FriendChange.Full, _graph.Accept(_mario, _luigi));
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _peach, Now));
    }

    [Fact]
    public void PruneDropsUnknownUsers()
    {
        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        _graph.Request(_peach, _mario, Now);

        Assert.True(_graph.Prune(id => id != _peach));
        Assert.Empty(_graph.IncomingOf(_mario));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.False(_graph.Prune(id => id != _peach));
    }

    [Fact]
    public void FileRoundTrip()
    {
        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        _graph.Request(_peach, _mario, Now);

        var copy = FriendGraph.FromFile(_graph.ToFile());
        Assert.True(copy.AreFriends(_mario, _luigi));
        var request = Assert.Single(copy.IncomingOf(_mario));
        Assert.Equal(_peach, request.From);
        Assert.Equal(Now, request.CreatedAt);
    }

    [Fact]
    public void FromFileRejectsBadIds()
    {
        Assert.Throws<FormatException>(() => FriendGraph.FromFile(new FriendFile { Friendships = [["x", "y"]] }));
        Assert.Throws<FormatException>(() => FriendGraph.FromFile(new FriendFile { Friendships = [["only-one"]] }));
        Assert.Throws<FormatException>(() =>
            FriendGraph.FromFile(new FriendFile { Requests = [new FriendFileRequest { From = null, To = "y" }] }));
    }
}
