namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un utente di Jellyfin, come serve agli amici. <paramref name="CanJoinParties"/>:
/// può usare i watch party (accesso SyncPlay diverso da nessuno).
/// <paramref name="IsAdmin"/>: amministratore di Jellyfin; per lui non vale
/// il recupero della password da soli (spec L §8).
/// <paramref name="CanManageSubtitles"/>: spunta "gestione sottotitoli" di Jellyfin (spec R §6.4).
/// </summary>
public sealed record UserRef(Guid Id, string Name, bool Enabled, bool CanJoinParties, bool IsAdmin = false, bool CanManageSubtitles = false);

/// <summary>Gli utenti del server (adattatore di IUserManager).</summary>
public interface IUserDirectory
{
    IReadOnlyList<UserRef> GetUsers();

    /// <summary>null se l'utente non esiste (più).</summary>
    UserRef? GetUser(Guid userId);
}
