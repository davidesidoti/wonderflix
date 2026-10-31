using Jellyfin.Plugin.WonderFlixWatchParty.Push;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Dispositivi con accesso: di default nessuno, i test li aggiungono con <see cref="Allow"/>.</summary>
internal sealed class FakeDeviceAccess : IDeviceAccess
{
    private readonly HashSet<(Guid, string)> _allowed = [];

    public void Allow(Guid userId, string deviceId) => _allowed.Add((userId, deviceId));

    public void Revoke(Guid userId, string deviceId) => _allowed.Remove((userId, deviceId));

    public bool HasAccess(Guid userId, string deviceId) => _allowed.Contains((userId, deviceId));
}
