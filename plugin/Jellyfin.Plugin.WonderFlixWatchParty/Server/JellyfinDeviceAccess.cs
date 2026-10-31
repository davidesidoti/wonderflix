using Jellyfin.Data.Queries;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using MediaBrowser.Controller.Devices;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// I dispositivi dell'utente secondo Jellyfin: Jellyfin toglie il dispositivo
/// al logout e alla revoca della sessione.
/// </summary>
public sealed class JellyfinDeviceAccess(IDeviceManager deviceManager) : IDeviceAccess
{
    public bool HasAccess(Guid userId, string deviceId) =>
        !string.IsNullOrEmpty(deviceId)
        && deviceManager.GetDevices(new DeviceQuery { UserId = userId, DeviceId = deviceId }).Items.Count > 0;
}
