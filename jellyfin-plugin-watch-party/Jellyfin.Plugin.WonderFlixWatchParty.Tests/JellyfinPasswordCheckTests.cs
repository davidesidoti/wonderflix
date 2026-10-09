using System.Security;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinPasswordCheckTests
{
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly IUserManager _users;
    private readonly InterfaceStub<IUserManager> _userStub;
    private readonly RecordingLogger<JellyfinPasswordCheck> _logger = new();
    private readonly JellyfinPasswordCheck _check;

    public JellyfinPasswordCheckTests()
    {
        (_users, _userStub) = InterfaceStub<IUserManager>.Create();
        _userStub.Handlers["GetUserById"] = args => (Guid)args[0]! == _mario.Id ? _mario : null;
        _check = new JellyfinPasswordCheck(_users, _logger);
    }

    [Fact]
    public async Task TheRightPasswordIsCheckedWithJellyfinAsALocalNonSessionLogin()
    {
        _userStub.Handlers["AuthenticateUser"] = _ => Task.FromResult<User?>(_mario);

        Assert.True(await _check.IsCurrentPasswordAsync(_mario.Id, "giusta"));

        var call = Assert.Single(_userStub.Calls, c => c.Name == "AuthenticateUser");
        Assert.Equal(new object?[] { "mario", "giusta", "127.0.0.1", false }, call.Args);
        Assert.Empty(_logger.Entries);
    }

    [Fact]
    public async Task NoUserBackMeansWrong()
    {
        _userStub.Handlers["AuthenticateUser"] = _ => Task.FromResult<User?>(null);

        Assert.False(await _check.IsCurrentPasswordAsync(_mario.Id, "sbagliata"));
    }

    [Fact]
    public async Task AnErrorFromJellyfinIsWrongAndIsLoggedWithoutThePassword()
    {
        _userStub.Handlers["AuthenticateUser"] = _ => Task.FromException<User?>(new SecurityException("utente disattivato"));

        Assert.False(await _check.IsCurrentPasswordAsync(_mario.Id, "password-segreta"));

        var entry = Assert.Single(_logger.Entries);
        Assert.Equal(LogLevel.Warning, entry.Level);
        Assert.Contains(_mario.Id.ToString("N"), entry.Message);
        Assert.Contains(nameof(SecurityException), entry.Message);
        Assert.DoesNotContain("password-segreta", entry.Message);
        Assert.DoesNotContain("password-segreta", entry.Exception?.ToString() ?? string.Empty);
    }

    [Fact]
    public async Task AnErrorThrownByTheCallItselfIsWrongToo()
    {
        _userStub.Handlers["AuthenticateUser"] = _ => throw new InvalidOperationException("database");

        Assert.False(await _check.IsCurrentPasswordAsync(_mario.Id, "giusta"));

        Assert.Equal(LogLevel.Warning, Assert.Single(_logger.Entries).Level);
    }

    [Fact]
    public async Task OnlyTheCancellationOfTheCallerComesOut()
    {
        _userStub.Handlers["AuthenticateUser"] = _ => Task.FromCanceled<User?>(new CancellationToken(canceled: true));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => _check.IsCurrentPasswordAsync(_mario.Id, "giusta"));
    }

    [Fact]
    public async Task AnUnknownUserIsWrongAndJellyfinIsNotAsked()
    {
        Assert.False(await _check.IsCurrentPasswordAsync(Guid.NewGuid(), "giusta"));
        Assert.False(await _check.IsCurrentPasswordAsync(Guid.Empty, "giusta"));

        Assert.DoesNotContain(_userStub.Calls, c => c.Name == "AuthenticateUser");
        Assert.DoesNotContain(_userStub.Calls, c => c.Name == "GetUserById" && (Guid)c.Args[0]! == Guid.Empty);
    }
}
