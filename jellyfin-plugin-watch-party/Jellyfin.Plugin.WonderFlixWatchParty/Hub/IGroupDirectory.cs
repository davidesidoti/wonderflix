namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>I gruppi SyncPlay (adattatore di ISyncPlayManager).</summary>
public interface IGroupDirectory
{
    /// <summary>
    /// I nomi utente dei partecipanti del gruppo, visto dalla sessione;
    /// null se il gruppo non esiste, l'utente non può vederlo o la sessione
    /// non c'è più.
    /// </summary>
    IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId);
}
