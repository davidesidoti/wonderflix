using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactRegistryTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 9, 12, 0, 0, TimeSpan.Zero);
    private readonly TempFolder _folder = new();
    private readonly Guid _mario = Guid.NewGuid();

    public void Dispose() => _folder.Dispose();

    private ContactRegistry Registry() => TestAccount.Registry(_folder);

    private static DiscordContact Discord() => new() { Id = "222222222222222222", Name = "mario", VerifiedAt = Now };

    private static EmailContact Email() => new() { Address = "mario@example.com", VerifiedAt = Now };

    [Fact]
    public void AnUnknownUserHasNoContacts()
    {
        var contacts = Registry().Get(_mario);

        Assert.False(contacts.HasContact);
        Assert.Null(contacts.LastReminderAt);
    }

    [Fact]
    public void ContactsAreSavedAndReadBack()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(_mario, Email());

        var reloaded = Registry().Get(_mario);

        Assert.Equal("222222222222222222", reloaded.Discord!.Id);
        Assert.Equal("mario@example.com", reloaded.Email!.Address);
        Assert.True(reloaded.HasContact);
    }

    [Fact]
    public void CopiesDoNotChangeTheRegistry()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());

        var copy = registry.Get(_mario);
        copy.Discord!.Name = "altro";
        copy.Email = Email();

        Assert.Equal("mario", registry.Get(_mario).Discord!.Name);
        Assert.Null(registry.Get(_mario).Email);
        Assert.Equal("mario", registry.All()[_mario].Discord!.Name);
    }

    [Fact]
    public void ChangingTheObjectAfterSetDoesNotChangeTheRegistry()
    {
        var registry = Registry();
        var discord = Discord();
        var email = Email();
        registry.SetDiscord(_mario, discord);
        registry.SetEmail(_mario, email);

        discord.Id = "333333333333333333";
        discord.Name = "altro";
        email.Address = "altro@example.com";

        var stored = registry.Get(_mario);
        Assert.Equal("222222222222222222", stored.Discord!.Id);
        Assert.Equal("mario", stored.Discord.Name);
        Assert.Equal("mario@example.com", stored.Email!.Address);
    }

    [Theory]
    [InlineData("abc", "mario")]
    [InlineData("", "mario")]
    [InlineData("22222222222222222", " ")]
    [InlineData("222222222222222222", "")]
    [InlineData("222222222222222222", " ")]
    public void AnInvalidDiscordIsRefusedAndNothingChanges(string id, string name)
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());
        var before = File.ReadAllText(_folder.ContactsFile);
        var luigi = Guid.NewGuid();
        var invalid = new DiscordContact { Id = id, Name = name, VerifiedAt = Now };

        Assert.Throws<ArgumentException>(() => registry.SetDiscord(_mario, invalid));
        Assert.Throws<ArgumentException>(() => registry.SetDiscord(luigi, invalid));

        Assert.Equal("mario", registry.Get(_mario).Discord!.Name);
        Assert.Equal(new[] { _mario }, registry.All().Keys);
        Assert.Equal(before, File.ReadAllText(_folder.ContactsFile));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    public void ABlankEmailIsRefusedAndNothingChanges(string address)
    {
        var registry = Registry();
        registry.SetEmail(_mario, Email());
        var before = File.ReadAllText(_folder.ContactsFile);
        var luigi = Guid.NewGuid();
        var invalid = new EmailContact { Address = address, VerifiedAt = Now };

        Assert.Throws<ArgumentException>(() => registry.SetEmail(_mario, invalid));
        Assert.Throws<ArgumentException>(() => registry.SetEmail(luigi, invalid));

        Assert.Equal("mario@example.com", registry.Get(_mario).Email!.Address);
        Assert.Equal(new[] { _mario }, registry.All().Keys);
        Assert.Equal(before, File.ReadAllText(_folder.ContactsFile));
    }

    [Fact]
    public void RemoveTakesOneChannelRemoveAllBoth()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(_mario, Email());

        Assert.True(registry.Remove(_mario, AccountChannel.Email));
        Assert.False(registry.Remove(_mario, AccountChannel.Email));
        Assert.NotNull(registry.Get(_mario).Discord);
        Assert.True(registry.RemoveAll(_mario));
        Assert.False(registry.RemoveAll(_mario));
        Assert.False(Registry().Get(_mario).HasContact);
    }

    [Fact]
    public void AUserWithNothingLeftLeavesTheFile()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());

        registry.RemoveAll(_mario);

        Assert.Empty(registry.All());
        Assert.DoesNotContain(_mario.ToString("N"), File.ReadAllText(_folder.ContactsFile));
    }

    [Fact]
    public void TheLastReminderStaysWithoutContacts()
    {
        var registry = Registry();
        registry.MarkReminded(_mario, Now);

        Assert.Equal(Now, Registry().Get(_mario).LastReminderAt);
        Assert.False(registry.RemoveAll(_mario));
        Assert.Equal(Now, registry.Get(_mario).LastReminderAt);
    }

    [Fact]
    public void PruneDropsTheUsersJellyfinNoLongerHas()
    {
        var registry = Registry();
        var luigi = Guid.NewGuid();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(luigi, Email());

        Assert.Equal(1, registry.Prune(id => id == _mario));

        Assert.Equal(new[] { _mario }, Registry().All().Keys);
        Assert.Equal(0, registry.Prune(id => id == _mario));
    }
}
