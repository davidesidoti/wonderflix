namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un utente di Jellyfin, come serve agli amici.</summary>
public sealed record UserRef(Guid Id, string Name, bool Enabled);

/// <summary>Gli utenti del server (adattatore di IUserManager).</summary>
public interface IUserDirectory
{
    IReadOnlyList<UserRef> GetUsers();

    /// <summary>null se l'utente non esiste (più).</summary>
    UserRef? GetUser(Guid userId);
}
