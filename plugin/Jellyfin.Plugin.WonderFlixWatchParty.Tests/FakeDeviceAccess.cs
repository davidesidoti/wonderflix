using Jellyfin.Plugin.WonderFlixWatchParty.Push;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Dispositivi con accesso: di default nessuno, i test li aggiungono con <see cref="Allow"/>.</summary>
internal sealed class FakeDeviceAccess : IDeviceAccess
{
    private readonly HashSet<(Guid, string)> _allowed = [];

    public void Allow(Guid userId, string deviceId) => _allowed.Add((userId, deviceId));

    public void Revoke(Guid userId, string deviceId) => _allowed.Remove((userId, deviceId));

    /// <summary>Dispositivi per cui il controllo lancia, come un errore del database di Jellyfin.</summary>
    public HashSet<string> Failing { get; } = [];

    /// <summary>Chiamato prima di ogni controllo (per simulare cosa succede nel frattempo).</summary>
    public Action<Guid, string>? BeforeCheck { get; set; }

    public bool HasAccess(Guid userId, string deviceId)
    {
        BeforeCheck?.Invoke(userId, deviceId);
        return Failing.Contains(deviceId)
            ? throw new InvalidOperationException("database non disponibile")
            : _allowed.Contains((userId, deviceId));
    }
}
