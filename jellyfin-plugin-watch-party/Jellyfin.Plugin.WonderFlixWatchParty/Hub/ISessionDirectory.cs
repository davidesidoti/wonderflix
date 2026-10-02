namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Le sessioni del server (adattatore di ISessionManager).</summary>
public interface ISessionDirectory
{
    /// <summary>
    /// La sessione di chi chiama, dal dispositivo, dal client e dall'utente
    /// dell'autenticazione; null se non c'è.
    /// </summary>
    CallerSession? FindCaller(string? deviceId, string? client, Guid userId);

    /// <summary>La sessione esiste ancora.</summary>
    bool Exists(string sessionId);
}
