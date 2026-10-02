namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Gruppo → sessioni WonderFlix registrate, con il nome utente di ciascuna
/// (spec E §6.5). Una sessione sta in un solo gruppo, come in SyncPlay.
/// Sicuro tra thread.
/// </summary>
public sealed class PartyRegistry
{
    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Dictionary<string, string>> _groups = [];

    public void Register(Guid groupId, string sessionId, string userName)
    {
        lock (_lock)
        {
            RemoveSessionLocked(sessionId);
            if (!_groups.TryGetValue(groupId, out var sessions))
            {
                sessions = new Dictionary<string, string>(StringComparer.Ordinal);
                _groups[groupId] = sessions;
            }

            sessions[sessionId] = userName;
        }
    }

    public bool IsRegistered(Guid groupId, string sessionId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var sessions) && sessions.ContainsKey(sessionId);
        }
    }

    public void Unregister(Guid groupId, string sessionId)
    {
        lock (_lock)
        {
            if (_groups.TryGetValue(groupId, out var sessions)
                && sessions.Remove(sessionId)
                && sessions.Count == 0)
            {
                _groups.Remove(groupId);
            }
        }
    }

    /// <summary>Toglie la sessione da qualunque gruppo.</summary>
    public void RemoveSession(string sessionId)
    {
        lock (_lock)
        {
            RemoveSessionLocked(sessionId);
        }
    }

    public IReadOnlyList<(string SessionId, string UserName)> GetSessions(Guid groupId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var sessions)
                ? sessions.Select(s => (SessionId: s.Key, UserName: s.Value)).ToList()
                : [];
        }
    }

    public IReadOnlyList<Guid> GetGroups()
    {
        lock (_lock)
        {
            return _groups.Keys.ToList();
        }
    }

    public void RemoveGroup(Guid groupId)
    {
        lock (_lock)
        {
            _groups.Remove(groupId);
        }
    }

    private void RemoveSessionLocked(string sessionId)
    {
        foreach (var (groupId, sessions) in _groups.ToList())
        {
            if (sessions.Remove(sessionId) && sessions.Count == 0)
            {
                _groups.Remove(groupId);
            }
        }
    }
}
