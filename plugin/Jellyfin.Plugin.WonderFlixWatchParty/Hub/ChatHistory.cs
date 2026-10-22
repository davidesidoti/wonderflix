using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Ultimi messaggi della chat di ogni gruppo, solo in memoria (spec E §6.5):
/// si perdono al riavvio del server. Sicuro tra thread.
/// </summary>
public sealed class ChatHistory
{
    /// <summary>Messaggi tenuti per gruppo.</summary>
    public const int Capacity = 50;

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Queue<StampedEvent>> _groups = [];

    public void Add(Guid groupId, StampedEvent message)
    {
        lock (_lock)
        {
            if (!_groups.TryGetValue(groupId, out var messages))
            {
                messages = new Queue<StampedEvent>();
                _groups[groupId] = messages;
            }

            messages.Enqueue(message);
            while (messages.Count > Capacity)
            {
                messages.Dequeue();
            }
        }
    }

    /// <summary>I messaggi del gruppo, dal più vecchio.</summary>
    public IReadOnlyList<StampedEvent> Get(Guid groupId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var messages) ? messages.ToList() : [];
        }
    }

    public IReadOnlyList<Guid> GetGroups()
    {
        lock (_lock)
        {
            return _groups.Keys.ToList();
        }
    }

    public void Remove(Guid groupId)
    {
        lock (_lock)
        {
            _groups.Remove(groupId);
        }
    }
}
