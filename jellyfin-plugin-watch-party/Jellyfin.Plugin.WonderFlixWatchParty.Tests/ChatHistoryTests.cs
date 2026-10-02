using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ChatHistoryTests
{
    private static StampedEvent Chat(string id) => new()
    {
        Id = id,
        GroupId = "g",
        Type = EventTypes.Chat,
        UserId = "u",
        UserName = "Mario",
        SentAt = "2026-10-02T21:00:00.000Z",
        Text = id,
    };

    [Fact]
    public void KeepsTheLast50InOrder()
    {
        var history = new ChatHistory();
        var group = Guid.NewGuid();
        for (var i = 1; i <= 55; i++)
        {
            history.Add(group, Chat($"m{i}"));
        }

        var messages = history.Get(group);
        Assert.Equal(ChatHistory.Capacity, messages.Count);
        Assert.Equal("m6", messages[0].Id);
        Assert.Equal("m55", messages[^1].Id);
    }

    [Fact]
    public void GroupsAreSeparateAndRemovable()
    {
        var history = new ChatHistory();
        var g1 = Guid.NewGuid();
        var g2 = Guid.NewGuid();
        history.Add(g1, Chat("a"));
        history.Add(g2, Chat("b"));
        Assert.Equal("a", Assert.Single(history.Get(g1)).Id);
        history.Remove(g1);
        Assert.Empty(history.Get(g1));
        Assert.Equal(g2, Assert.Single(history.GetGroups()));
    }
}
