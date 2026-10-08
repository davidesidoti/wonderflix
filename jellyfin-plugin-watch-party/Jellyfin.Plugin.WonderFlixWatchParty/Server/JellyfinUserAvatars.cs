using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Gli utenti chiesti, con il tag dell'immagine che Jellyfin mette in
/// UserDto.PrimaryImageTag (spec K §7.2). Elenca gli utenti una volta e
/// confronta in memoria: con Jellyfin 10.11.9 ogni GetUserById o
/// GetUserByName è una query, e GetUserByName lancia con un nome vuoto.
/// </summary>
public sealed class JellyfinUserAvatars(IUserManager userManager, IImageProcessor imageProcessor) : IUserAvatars
{
    private static readonly Func<object, IEnumerable<User>>? ListUsers = UserListing.For(typeof(IUserManager));

    public IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names)
    {
        if (ids.Count == 0 && names.Count == 0)
        {
            return [];
        }

        var wantedIds = ids.ToHashSet();
        var wantedNames = names.ToHashSet(StringComparer.OrdinalIgnoreCase);
        // Ogni utente compare una volta nell'elenco: niente doppioni.
        return (ListUsers ?? throw new MissingMemberException(typeof(IUserManager).FullName, "GetUsers"))(userManager)
            .Where(user => !user.HasPermission(PermissionKind.IsDisabled))
            .Where(user => wantedIds.Contains(user.Id) || wantedNames.Contains(user.Username))
            .Select(user => new UserAvatarInfo(user.Id, user.Username, imageProcessor.GetImageCacheTag(user)))
            .ToList();
    }
}
