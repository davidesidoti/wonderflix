using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
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
        var reset = new JellyfinPasswordReset(users, sessions, NullLogger<JellyfinPasswordReset>.Instance);

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
        var reset = new JellyfinPasswordReset(users, sessions, NullLogger<JellyfinPasswordReset>.Instance);

        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.NewGuid(), "nuova-password"));
        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.Empty, "nuova-password"));
        Assert.Empty(sessionStub.Calls);
    }

    [Fact]
    public async Task AFailedChangeComesOutAndNoSessionCloses()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUserById"] = _ => mario;
        userStub.Handlers["ChangePassword"] = _ => Task.FromException(new InvalidOperationException("database"));
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        var reset = new JellyfinPasswordReset(users, sessions, NullLogger<JellyfinPasswordReset>.Instance);

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => reset.ResetAsync(mario.Id, "nuova-password"));

        Assert.Equal("database", error.Message);
        Assert.DoesNotContain(sessionStub.Calls, c => c.Name == "RevokeUserTokens");
    }

    [Fact]
    public async Task AFailedRevokeIsLoggedNotThrownBecauseThePasswordDidChange()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUserById"] = _ => mario;
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        sessionStub.Handlers["RevokeUserTokens"] = _ => Task.FromException(new InvalidOperationException("sessioni"));
        var logger = new RecordingLogger<JellyfinPasswordReset>();
        var reset = new JellyfinPasswordReset(users, sessions, logger);

        await reset.ResetAsync(mario.Id, "nuova-password");

        Assert.Single(userStub.Calls, c => c.Name == "ChangePassword");
        var entry = Assert.Single(logger.Entries, e => e.Level == LogLevel.Error);
        Assert.IsType<InvalidOperationException>(entry.Exception);
        Assert.Contains(mario.Id.ToString("N"), entry.Message);
        Assert.DoesNotContain("nuova-password", entry.Message);
    }
}
