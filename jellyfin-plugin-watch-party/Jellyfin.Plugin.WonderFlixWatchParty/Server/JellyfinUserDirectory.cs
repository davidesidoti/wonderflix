using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Gli utenti di Jellyfin.</summary>
public sealed class JellyfinUserDirectory(IUserManager userManager) : IUserDirectory
{
    public IReadOnlyList<UserRef> GetUsers() => userManager.Users.Select(ToRef).ToList();

    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public UserRef? GetUser(Guid userId) =>
        userId != Guid.Empty && userManager.GetUserById(userId) is { } user ? ToRef(user) : null;

    private static UserRef ToRef(User user) =>
        new(user.Id, user.Username, !user.HasPermission(PermissionKind.IsDisabled));
}
