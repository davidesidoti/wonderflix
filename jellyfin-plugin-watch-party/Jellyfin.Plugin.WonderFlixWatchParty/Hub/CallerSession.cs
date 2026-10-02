namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Chi chiama: la sua sessione Jellyfin e il suo utente.</summary>
public sealed record CallerSession(string SessionId, Guid UserId, string UserName);
