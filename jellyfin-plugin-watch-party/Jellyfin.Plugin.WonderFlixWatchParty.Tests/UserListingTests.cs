using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UserListingTests
{
    // La forma di IUserManager in Jellyfin 10.11.0: una proprietà.
    public interface IOldUserManager
    {
        IEnumerable<User> Users { get; }
    }

    // La forma di IUserManager in Jellyfin 10.11.9: un metodo.
    public interface INewUserManager
    {
        IEnumerable<User> GetUsers();
    }

    private sealed class OldUserManager(IEnumerable<User> users) : IOldUserManager
    {
        public IEnumerable<User> Users { get; } = users;
    }

    private sealed class NewUserManager(IEnumerable<User> users) : INewUserManager
    {
        public IEnumerable<User> GetUsers() => users;
    }

    private static User[] SomeUsers() => [new("Mario", "provider", "reset"), new("Luigi", "provider", "reset")];

    [Fact]
    public void ListsUsersFromThePropertyOfJellyfin10110()
    {
        var users = SomeUsers();

        var list = UserListing.For(typeof(IOldUserManager));

        Assert.NotNull(list);
        Assert.Equal(users, list!(new OldUserManager(users)));
    }

    [Fact]
    public void ListsUsersFromTheMethodOfLaterJellyfin()
    {
        var users = SomeUsers();

        var list = UserListing.For(typeof(INewUserManager));

        Assert.NotNull(list);
        Assert.Equal(users, list!(new NewUserManager(users)));
    }

    [Fact]
    public void ReturnsNullWhenTheTypeHasNeitherMember()
    {
        Assert.Null(UserListing.For(typeof(IDisposable)));
    }
}
