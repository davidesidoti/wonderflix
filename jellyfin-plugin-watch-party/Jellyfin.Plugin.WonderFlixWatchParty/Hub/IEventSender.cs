namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Invio di un evento a una sessione, sul suo WebSocket.</summary>
public interface IEventSender
{
    /// <summary>Manda payload alla sessione; false se la sessione non esiste più.</summary>
    Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken);
}
