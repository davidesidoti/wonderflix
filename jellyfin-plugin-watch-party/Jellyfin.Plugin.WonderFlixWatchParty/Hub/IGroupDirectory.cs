namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un gruppo SyncPlay come lo vede una sessione.</summary>
public sealed record GroupSummary(Guid Id, string Name, string State, IReadOnlyList<string> Participants);

/// <summary>I gruppi SyncPlay (adattatore di ISyncPlayManager).</summary>
public interface IGroupDirectory
{
    /// <summary>
    /// I nomi utente dei partecipanti del gruppo, visto dalla sessione;
    /// null se il gruppo non esiste, l'utente non può vederlo o la sessione
    /// non c'è più.
    /// </summary>
    IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId);

    /// <summary>
    /// I gruppi visti dalla sessione (quelli di cui l'utente può vedere la
    /// coda); vuoto se la sessione non c'è.
    /// </summary>
    IReadOnlyList<GroupSummary> ListGroups(string sessionId);

    /// <summary>Il gruppo visto dalla sessione; null come per <see cref="GetParticipants"/>.</summary>
    GroupSummary? GetGroup(string sessionId, Guid groupId);
}
