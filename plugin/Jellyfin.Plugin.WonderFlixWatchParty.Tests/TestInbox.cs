using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>La cassetta delle notifiche dei test: server finto e file in una cartella temporanea.</summary>
internal static class TestInbox
{
    public static InboxService Create(FakeServer server, TempFolder folder, TimeProvider time) =>
        new(
            new InboxStore(folder.InboxFile, NullLogger<InboxStore>.Instance),
            server, server, server, server, time, NullLogger<InboxService>.Instance);
}
