using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Gli utenti di Jellyfin.</summary>
public sealed class JellyfinUserDirectory(IUserManager userManager) : IUserDirectory
{
    // In 10.11.0 IUserManager ha la proprietà Users, nelle 10.11.x successive il
    // metodo GetUsers(): quale usare si decide una volta sola a runtime (vedi
    // UserListing).
    private static readonly Func<object, IEnumerable<User>>? ListUsers = UserListing.For(typeof(IUserManager));

    public IReadOnlyList<UserRef> GetUsers() =>
        (ListUsers ?? throw new MissingMemberException(typeof(IUserManager).FullName, "GetUsers"))(userManager)
            .Select(ToRef)
            .ToList();

    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public UserRef? GetUser(Guid userId) =>
        userId != Guid.Empty && userManager.GetUserById(userId) is { } user ? ToRef(user) : null;

    private static UserRef ToRef(User user) => new(
        user.Id,
        user.Username,
        !user.HasPermission(PermissionKind.IsDisabled),
        user.SyncPlayAccess != SyncPlayUserAccessType.None);
}
