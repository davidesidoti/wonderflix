using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactStoreTests : IDisposable
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly DateTimeOffset Now = new(2026, 10, 9, 12, 0, 0, TimeSpan.Zero);
    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private ContactStore Store(ILogger<ContactStore>? logger = null) =>
        new(_folder.ContactsFile, logger ?? NullLogger<ContactStore>.Instance);

    [Fact]
    public void AMissingFileIsEmpty() => Assert.Empty(Store().Load());

    [Fact]
    public void ContactsSurviveTheFile()
    {
        var store = Store();
        store.Save(new Dictionary<Guid, UserContacts>
        {
            [Mario] = new()
            {
                Discord = new DiscordContact { Id = "222222222222222222", Name = "mario", VerifiedAt = Now },
                Email = new EmailContact { Address = "mario@example.com", VerifiedAt = Now },
                LastReminderAt = Now.AddDays(-1),
            },
        });

        var read = Assert.Single(store.Load());

        Assert.Equal(Mario, read.Key);
        Assert.Equal("222222222222222222", read.Value.Discord!.Id);
        Assert.Equal("mario", read.Value.Discord.Name);
        Assert.Equal(Now, read.Value.Discord.VerifiedAt);
        Assert.Equal("mario@example.com", read.Value.Email!.Address);
        Assert.Equal(Now.AddDays(-1), read.Value.LastReminderAt);
        var text = File.ReadAllText(_folder.ContactsFile);
        Assert.Contains("\"Users\"", text);
        Assert.Contains(Mario.ToString("N"), text);
        Assert.False(File.Exists(_folder.ContactsFile + ".tmp"));
    }

    [Theory]
    [InlineData("non è json")]
    [InlineData("null")]
    [InlineData("""{"Users":{"non-un-guid":{}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":null}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Discord":{"Id":"abc","Name":"mario"}}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Discord":{"Id":"222222222222222222","Name":" "}}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Email":{"Address":""}}}}""")]
    public void AnUnreadableFileMovesToBadAndStartsEmpty(string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ContactsFile)!);
        File.WriteAllText(_folder.ContactsFile, content);
        var logger = new RecordingLogger<ContactStore>();

        Assert.Empty(Store(logger).Load());

        Assert.False(File.Exists(_folder.ContactsFile));
        Assert.Equal(content, File.ReadAllText(_folder.ContactsFile + ".bad"));
        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
    }
}
