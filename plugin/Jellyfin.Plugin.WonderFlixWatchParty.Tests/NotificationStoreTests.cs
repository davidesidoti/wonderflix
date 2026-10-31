using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NotificationStoreTests : IDisposable
{
    private static readonly Guid Mario = Guid.NewGuid();

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private NotificationStore Store() => new(_folder.NotificationsFile, NullLogger<NotificationStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().For(Mario));
        Assert.False(File.Exists(_folder.NotificationsFile));
    }

    [Fact]
    public void Book_DisabledTypeSurvivesRoundTrip()
    {
        var book = new NotificationBook();
        book.Upsert(new PushSubscription
        {
            UserId = Mario, Endpoint = "https://push/1", P256dh = "p", Auth = "a", DeviceId = "d", Language = "it",
            CreatedAt = new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero),
        });
        book.SetEnabled(Mario, "Invite", false);

        Store().Save(book);
        var loaded = Store().Load();

        Assert.False(File.Exists(_folder.NotificationsFile + ".tmp"));
        Assert.False(loaded.IsEnabled(Mario, "Invite"));
        Assert.True(loaded.IsEnabled(Mario, "Announcement"));
        var sub = Assert.Single(loaded.For(Mario));
        Assert.Equal(("https://push/1", "p", "a", "d", "it"), (sub.Endpoint, sub.P256dh, sub.Auth, sub.DeviceId, sub.Language));
        Assert.Equal(new DateTimeOffset(2026, 10, 31, 12, 0, 0, TimeSpan.Zero), sub.CreatedAt);
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.NotificationsFile)!);
        File.WriteAllText(_folder.NotificationsFile, "{ non è json");

        Assert.Empty(Store().Load().For(Mario));

        Assert.False(File.Exists(_folder.NotificationsFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.NotificationsFile + ".bad"));
    }

    [Fact]
    public void SubscriptionWithoutEndpointIsUnreadable()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.NotificationsFile)!);
        File.WriteAllText(_folder.NotificationsFile, $$"""{"Subscriptions":[{"UserId":"{{Mario}}"}]}""");

        Assert.Empty(Store().Load().For(Mario));

        Assert.True(File.Exists(_folder.NotificationsFile + ".bad"));
    }
}

public class VapidKeyProviderTests
{
    [Fact]
    public void Provider_GeneratesOnceAndReuses()
    {
        var config = new PluginConfiguration();
        var saves = 0;
        var provider = new VapidKeyProvider(() => config, () => saves++);

        var first = provider.Get();
        var second = provider.Get();

        Assert.Equal(first, second);
        Assert.Equal(1, saves);
        Assert.Equal(first.PublicKey, config.VapidPublicKey);
        Assert.Equal(first.PrivateKey, config.VapidPrivateKey);
        Assert.Equal(65, Base64Url.Decode(first.PublicKey).Length);
    }

    [Fact]
    public void Provider_KeepsKeysAlreadyInTheConfiguration()
    {
        var config = new PluginConfiguration { VapidPublicKey = "pub", VapidPrivateKey = "priv" };
        var saves = 0;

        Assert.Equal(new VapidKeys("pub", "priv"), new VapidKeyProvider(() => config, () => saves++).Get());
        Assert.Equal(0, saves);
    }

    [Fact]
    public void Provider_WithoutPluginKeepsTheKeysInMemory()
    {
        var provider = new VapidKeyProvider(() => null, () => throw new InvalidOperationException());

        Assert.Equal(provider.Get(), provider.Get());
    }
}
