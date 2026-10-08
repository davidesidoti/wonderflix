using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UserAvatarsTests
{
    private readonly User _mario = new("Mario", "provider", "reset") { ProfileImage = new ImageInfo("mario.png") };
    private readonly User _luigi = new("Luigi", "provider", "reset");
    private readonly User _bowser = new("Bowser", "provider", "reset") { ProfileImage = new ImageInfo("bowser.png") };

    private (JellyfinUserAvatars Avatars, InterfaceStub<IUserManager> Users) Create()
    {
        _bowser.SetPermission(PermissionKind.IsDisabled, true);
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUsers"] = _ => new[] { _mario, _luigi, _bowser };
        var (images, imageStub) = InterfaceStub<IImageProcessor>.Create();
        // Come Jellyfin: un tag solo con l'immagine.
        imageStub.Handlers["GetImageCacheTag"] = args =>
            args[0] is User { ProfileImage: not null } user ? "tag-" + user.Username : null;
        return (new JellyfinUserAvatars(users, images), userStub);
    }

    [Fact]
    public void FindsUsersByIdAndByNameIgnoringCase()
    {
        var (avatars, _) = Create();

        var found = avatars.Find([_mario.Id], ["LUIGI"]);

        Assert.Equal(new[] { "Mario", "Luigi" }, found.Select(user => user.Name));
        Assert.Equal(_mario.Id, found[0].Id);
        Assert.Equal("tag-Mario", found[0].ImageTag);
        Assert.Null(found[1].ImageTag);
    }

    [Fact]
    public void NamesWithNonAsciiLettersIgnoreCaseToo()
    {
        var elena = new User("Èlena", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUsers"] = _ => new[] { elena };
        var (images, _) = InterfaceStub<IImageProcessor>.Create();

        var found = Assert.Single(new JellyfinUserAvatars(users, images).Find([], ["èlena"]));

        Assert.Equal("Èlena", found.Name);
    }

    [Fact]
    public void TheSameUserOnlyOnce()
    {
        var (avatars, _) = Create();

        var found = Assert.Single(avatars.Find([_mario.Id], ["mario"]));

        Assert.Equal(_mario.Id, found.Id);
    }

    [Fact]
    public void DisabledAndUnknownUsersAreMissing()
    {
        var (avatars, _) = Create();

        Assert.Empty(avatars.Find([_bowser.Id, Guid.NewGuid(), Guid.Empty], ["bowser", "nessuno"]));
    }

    [Fact]
    public void NothingAskedNothingRead()
    {
        var (avatars, users) = Create();

        Assert.Empty(avatars.Find([], []));
        Assert.Empty(users.Calls);
    }
}
