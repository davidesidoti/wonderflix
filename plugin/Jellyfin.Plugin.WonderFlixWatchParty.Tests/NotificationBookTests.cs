using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NotificationBookTests
{
    private static readonly Guid Mario = Guid.NewGuid();
    private static readonly Guid Anna = Guid.NewGuid();

    private static PushSubscription Sub(Guid user, string endpoint, string auth = "a") =>
        new() { UserId = user, Endpoint = endpoint, P256dh = "p", Auth = auth, DeviceId = "d", Language = "it" };

    [Fact]
    public void Book_UpsertReplacesSameEndpointAndUser()
    {
        var book = new NotificationBook();
        book.Upsert(Sub(Mario, "https://push/1", "vecchia"));
        book.Upsert(Sub(Mario, "https://push/1", "nuova"));

        Assert.Equal("nuova", Assert.Single(book.For(Mario)).Auth);
    }

    [Fact]
    public void Book_SameEndpointTwoUsersAreTwoSubscriptions()
    {
        var book = new NotificationBook();
        book.Upsert(Sub(Mario, "https://push/1"));
        book.Upsert(Sub(Anna, "https://push/1"));

        Assert.Single(book.For(Mario));
        Assert.Single(book.For(Anna));

        Assert.True(book.Remove(Mario, "https://push/1"));
        Assert.Empty(book.For(Mario));
        Assert.Single(book.For(Anna));
        Assert.False(book.Remove(Mario, "https://push/1"));
    }

    [Fact]
    public void Book_RemoveEndpointRemovesItForEveryone()
    {
        var book = new NotificationBook();
        book.Upsert(Sub(Mario, "https://push/1"));
        book.Upsert(Sub(Anna, "https://push/1"));
        book.Upsert(Sub(Anna, "https://push/2"));

        Assert.True(book.RemoveEndpoint("https://push/1"));

        Assert.Empty(book.For(Mario));
        Assert.Equal("https://push/2", Assert.Single(book.For(Anna)).Endpoint);
        Assert.False(book.RemoveEndpoint("https://push/1"));
    }

    [Fact]
    public void Book_TypesAreEnabledUntilSwitchedOff()
    {
        var book = new NotificationBook();

        Assert.True(book.IsEnabled(Mario, "Invite"));
        Assert.True(book.SetEnabled(Mario, "Invite", false));
        Assert.False(book.SetEnabled(Mario, "Invite", false));
        Assert.False(book.IsEnabled(Mario, "Invite"));
        Assert.True(book.IsEnabled(Anna, "Invite"));
        Assert.True(book.SetEnabled(Mario, "Invite", true));
        Assert.False(book.SetEnabled(Mario, "Invite", true));
        Assert.True(book.IsEnabled(Mario, "Invite"));
    }

    [Fact]
    public void Book_BeyondTheCapDropsTheUsersOldest()
    {
        var book = new NotificationBook();
        var start = new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero);
        book.Upsert(Sub(Anna, "https://push/anna"));
        for (var i = 0; i <= NotificationBook.MaxPerUser; i++)
        {
            var sub = Sub(Mario, $"https://push/{i}");
            // La 0 è la più vecchia ma arriva per seconda: conta CreatedAt, non l'ordine.
            sub.CreatedAt = start.AddMinutes(i == 0 ? -1 : i == 1 ? -2 : i);
            book.Upsert(sub);
        }

        var mine = book.For(Mario);
        Assert.Equal(NotificationBook.MaxPerUser, mine.Count);
        Assert.DoesNotContain(mine, s => s.Endpoint == "https://push/1");
        Assert.Single(book.For(Anna));
    }

    [Fact]
    public void Book_PruneDropsSubscriptionsAndPreferencesOfMissingUsers()
    {
        var book = new NotificationBook();
        book.Upsert(Sub(Mario, "https://push/1"));
        book.Upsert(Sub(Mario, "https://push/2"));
        book.Upsert(Sub(Anna, "https://push/3"));
        book.SetEnabled(Mario, "Invite", false);

        Assert.Equal(2, book.Prune(user => user == Anna));

        Assert.Empty(book.For(Mario));
        Assert.Single(book.For(Anna));
        Assert.True(book.IsEnabled(Mario, "Invite"));
    }
}
