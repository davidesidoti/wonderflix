using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Controller.SyncPlay.Requests;
using MediaBrowser.Model.SyncPlay;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager,
    TimeProvider time,
    ILogger<JellyfinGroupDirectory> logger) : IGroupDirectory
{
    /// <summary>
    /// Ogni quanto lo stesso errore di SyncPlay finisce di nuovo nel log per
    /// intero (Warning con lo stack). Un gruppo con la coda rotta fallisce a
    /// ogni lettura (elenco dei party, amici, pulizia: circa ogni 30 s per
    /// client); in mezzo, Debug senza stack.
    /// </summary>
    public static readonly TimeSpan FailureLogInterval = TimeSpan.FromMinutes(10);

    /// <summary>Quanti errori diversi (gruppi, più l'elenco) si ricordano al massimo.</summary>
    public const int MaxRememberedFailures = 100;

    /// <summary>La chiave degli errori dell'elenco, che non sono di un gruppo.</summary>
    private static readonly Guid ListFailureKey = Guid.Empty;

    private readonly Lock _lock = new();

    /// <summary>Gruppo (o <see cref="ListFailureKey"/>) → ultimo errore scritto per intero.</summary>
    private readonly Dictionary<Guid, DateTimeOffset> _lastWarnings = [];

    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        GetGroup(sessionId, groupId)?.Participants;

    // Jellyfin 10.11.9: Group.HasAccessToQueue chiama IsVisibleStandalone
    // sugli elementi in coda, anche su quelli che non esistono più, e
    // ListGroups/GetGroup vanno in NullReferenceException. Un errore di
    // SyncPlay qui non deve diventare un 500 di Friends o Parties: si
    // risponde "nessun gruppo" e si scrive nel log (per intero una volta
    // ogni FailureLogInterval).
    public IReadOnlyList<GroupSummary> ListGroups(string sessionId)
    {
        var session = Find(sessionId);
        if (session is null)
        {
            return [];
        }

        try
        {
            return syncPlayManager.ListGroups(session, new ListGroupsRequest()).Select(ToSummary).ToList();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (ShouldWarn(ListFailureKey))
            {
                logger.LogWarning(ex, "Elenco dei gruppi SyncPlay non riuscito");
            }
            else
            {
                logger.LogDebug("Elenco dei gruppi SyncPlay non riuscito, di nuovo: {Error}", ex.Message);
            }

            return [];
        }
    }

    public GroupSummary? GetGroup(string sessionId, Guid groupId)
    {
        var session = Find(sessionId);
        if (session is null)
        {
            return null;
        }

        try
        {
            // GetGroup restituisce null se il gruppo non esiste o l'utente non
            // può vederne la coda.
            return syncPlayManager.GetGroup(session, groupId) is { } group ? ToSummary(group) : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (ShouldWarn(groupId))
            {
                logger.LogWarning(ex, "Gruppo SyncPlay {GroupId} non letto", groupId);
            }
            else
            {
                logger.LogDebug("Gruppo SyncPlay {GroupId} non letto, di nuovo: {Error}", groupId, ex.Message);
            }

            return null;
        }
    }

    /// <summary>
    /// Il primo errore di key, o il primo dopo <see cref="FailureLogInterval"/>,
    /// va scritto per intero. Oltre <see cref="MaxRememberedFailures"/> si
    /// tolgono le voci scadute; se sono tutte recenti, si riparte da capo.
    /// </summary>
    private bool ShouldWarn(Guid key)
    {
        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (_lastWarnings.TryGetValue(key, out var last) && now - last < FailureLogInterval)
            {
                return false;
            }

            if (_lastWarnings.Count >= MaxRememberedFailures)
            {
                foreach (var old in _lastWarnings.Where(w => now - w.Value >= FailureLogInterval).Select(w => w.Key).ToList())
                {
                    _lastWarnings.Remove(old);
                }

                if (_lastWarnings.Count >= MaxRememberedFailures)
                {
                    _lastWarnings.Clear();
                }
            }

            _lastWarnings[key] = now;
            return true;
        }
    }

    private SessionInfo? Find(string sessionId) =>
        sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));

    private static GroupSummary ToSummary(GroupInfoDto group) =>
        new(group.GroupId, group.GroupName, group.State.ToString(), group.Participants);
}
