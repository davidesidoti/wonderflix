using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PasswordChangingTests
{
    // La forma di IUserManager in Jellyfin 10.11.0: l'utente.
    public interface IOldPasswords
    {
        Task ChangePassword(User user, string newPassword);
    }

    // La forma di IUserManager in Jellyfin 10.11.9: l'id.
    public interface INewPasswords
    {
        Task ChangePassword(Guid userId, string newPassword);
    }

    private sealed class OldPasswords : IOldPasswords
    {
        public List<(User User, string Password)> Calls { get; } = [];

        public Task ChangePassword(User user, string newPassword)
        {
            Calls.Add((user, newPassword));
            return Task.CompletedTask;
        }
    }

    private sealed class NewPasswords : INewPasswords
    {
        public List<(Guid UserId, string Password)> Calls { get; } = [];

        public Task ChangePassword(Guid userId, string newPassword)
        {
            Calls.Add((userId, newPassword));
            return Task.CompletedTask;
        }
    }

    // Un manager con tutte e due le forme: deve vincere quella con l'id.
    public interface IBothPasswords
    {
        Task ChangePassword(User user, string newPassword);

        Task ChangePassword(Guid userId, string newPassword);
    }

    private sealed class BothPasswords : IBothPasswords
    {
        public List<string> Calls { get; } = [];

        public Task ChangePassword(User user, string newPassword)
        {
            Calls.Add("user");
            return Task.CompletedTask;
        }

        public Task ChangePassword(Guid userId, string newPassword)
        {
            Calls.Add("id");
            return Task.CompletedTask;
        }
    }

    private sealed class FailingPasswords : INewPasswords
    {
        public Task ChangePassword(Guid userId, string newPassword) => throw new InvalidOperationException("database");
    }

    [Fact]
    public async Task ChangesByUserOnJellyfin10110()
    {
        var mario = new User("Mario", "provider", "reset");
        var manager = new OldPasswords();

        var change = PasswordChanging.For(typeof(IOldPasswords));

        Assert.NotNull(change);
        await change!(manager, mario, "nuova-password");
        Assert.Equal(new[] { (mario, "nuova-password") }, manager.Calls);
    }

    [Fact]
    public async Task ChangesByIdOnLaterJellyfin()
    {
        var mario = new User("Mario", "provider", "reset");
        var manager = new NewPasswords();

        var change = PasswordChanging.For(typeof(INewPasswords));

        Assert.NotNull(change);
        await change!(manager, mario, "nuova-password");
        Assert.Equal(new[] { (mario.Id, "nuova-password") }, manager.Calls);
    }

    [Fact]
    public async Task WithBothFormsTheOneWithTheIdIsUsed()
    {
        var manager = new BothPasswords();

        var change = PasswordChanging.For(typeof(IBothPasswords));

        Assert.NotNull(change);
        await change!(manager, new User("Mario", "provider", "reset"), "nuova-password");
        Assert.Equal(new[] { "id" }, manager.Calls);
    }

    [Fact]
    public async Task AnErrorOfJellyfinComesOutAsItIs()
    {
        var change = PasswordChanging.For(typeof(INewPasswords))!;

        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => change(new FailingPasswords(), new User("Mario", "provider", "reset"), "nuova-password"));

        Assert.Equal("database", error.Message);
    }

    [Fact]
    public void ReturnsNullWhenTheTypeHasNoChangePassword() =>
        Assert.Null(PasswordChanging.For(typeof(IDisposable)));

    [Fact]
    public void TheJellyfinOfTheTestsHasOne() =>
        Assert.NotNull(PasswordChanging.For(typeof(IUserManager)));
}
