namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>Se un dispositivo Jellyfin ha ancora una sessione valida per l'utente (spec V: dopo il logout o la revoca l'iscrizione va tolta).</summary>
public interface IDeviceAccess
{
    bool HasAccess(Guid userId, string deviceId);
}
