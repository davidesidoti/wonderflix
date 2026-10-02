namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi di evento del protocollo (spec E §6.3).</summary>
public static class EventTypes
{
    public const string Action = "Action";
    public const string Chat = "Chat";
    public const string Reaction = "Reaction";
}
