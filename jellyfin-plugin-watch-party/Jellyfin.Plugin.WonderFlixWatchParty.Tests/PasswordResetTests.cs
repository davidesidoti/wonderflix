using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PasswordResetTests
{
    [Fact]
    public async Task ThePasswordChangesThenEverySessionCloses()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUserById"] = args => (Guid)args[0]! == mario.Id ? mario : null;
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        var reset = new JellyfinPasswordReset(users, sessions);

        await reset.ResetAsync(mario.Id, "nuova-password");

        var change = Assert.Single(userStub.Calls, c => c.Name == "ChangePassword");
        Assert.Equal(new object?[] { mario.Id, "nuova-password" }, change.Args);
        var revoke = Assert.Single(sessionStub.Calls, c => c.Name == "RevokeUserTokens");
        Assert.Equal(new object?[] { mario.Id, string.Empty }, revoke.Args);
    }

    [Fact]
    public async Task AnUnknownUserIsAnError()
    {
        var (users, _) = InterfaceStub<IUserManager>.Create();
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        var reset = new JellyfinPasswordReset(users, sessions);

        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.NewGuid(), "nuova-password"));
        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.Empty, "nuova-password"));
        Assert.Empty(sessionStub.Calls);
    }
}
