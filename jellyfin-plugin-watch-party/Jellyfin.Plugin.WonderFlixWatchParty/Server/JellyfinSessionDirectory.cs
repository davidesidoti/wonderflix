using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le sessioni di Jellyfin.</summary>
public sealed class JellyfinSessionDirectory(ISessionManager sessionManager) : ISessionDirectory
{
    public CallerSession? FindCaller(string? deviceId, string? client, Guid userId)
    {
        if (string.IsNullOrEmpty(deviceId) || userId == Guid.Empty)
        {
            return null;
        }

        // Jellyfin distingue le sessioni per client e dispositivo.
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.DeviceId, deviceId, StringComparison.Ordinal)
            && string.Equals(s.Client, client, StringComparison.Ordinal)
            && s.UserId.Equals(userId));
        return session is null ? null : new CallerSession(session.Id, session.UserId, session.UserName);
    }

    public bool Exists(string sessionId) =>
        sessionManager.Sessions.Any(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));
}
