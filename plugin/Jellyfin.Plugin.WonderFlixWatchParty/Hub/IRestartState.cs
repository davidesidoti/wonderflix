namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Se Jellyfin ha bisogno di un riavvio (spec V): un'installazione o un aggiornamento di plugin lo chiede.</summary>
public interface IRestartState
{
    bool PendingRestart { get; }
}
