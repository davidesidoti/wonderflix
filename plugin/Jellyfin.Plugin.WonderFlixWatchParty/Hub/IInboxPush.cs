using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Dove la cassetta porta le voci nuove (spec V): la push. Non lancia e non blocca.</summary>
public interface IInboxPush
{
    void Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh);
}
