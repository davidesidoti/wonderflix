using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InboxRequestsTests
{
    [Fact]
    public void ARequestEntryReplacesTheOneOfTheSameTypeAndRequest()
    {
        var book = new InboxBook();
        var user = Guid.NewGuid();
        var now = DateTimeOffset.UnixEpoch;
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 1, Title = "A", CreatedAt = now });
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestAvailable, RequestId = 1, Title = "A", CreatedAt = now });
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 2, Title = "B", CreatedAt = now });
        book.MarkRead(user, long.MaxValue);

        var again = book.UpsertRequest(
            user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 1, Title = "A2", CreatedAt = now });

        var entries = book.List(user);
        Assert.Equal(new[] { "A2", "B", "A" }, entries.Select(e => e.Title));
        Assert.Equal(again.Id, entries[0].Id);
        Assert.False(entries[0].Read);
        Assert.Equal(InboxEntryTypes.RequestAvailable, entries[2].Type);
    }

    [Fact]
    public void RequestFieldsAreWrittenOnlyWhenSet()
    {
        var json = JsonSerializer.Serialize(new InboxEntry
        {
            Id = "x",
            Type = InboxEntryTypes.RequestAvailable,
            RequestId = 53,
            MediaType = "tv",
            TmdbId = 9,
            Title = "Brothers (2026)",
            Seasons = [1, 2],
            ItemId = "6d1c8ea33a794f76fdbe92a216959073",
        });

        Assert.Contains("\"RequestId\":53", json, StringComparison.Ordinal);
        Assert.Contains("\"MediaType\":\"tv\"", json, StringComparison.Ordinal);
        Assert.Contains("\"TmdbId\":9", json, StringComparison.Ordinal);
        Assert.Contains("\"Seasons\":[1,2]", json, StringComparison.Ordinal);
        Assert.Contains("\"ItemId\":\"6d1c8ea33a794f76fdbe92a216959073\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("RequesterName", json, StringComparison.Ordinal);
        Assert.DoesNotContain("GroupId", json, StringComparison.Ordinal);
        Assert.DoesNotContain("RequestId", JsonSerializer.Serialize(new InboxEntry { Type = InboxEntryTypes.Announcement }), StringComparison.Ordinal);
    }
}
