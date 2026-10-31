using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Un DownloadService per i test che lo usano da fuori (nudge, controller, timer): il file non si tocca finché non serve.</summary>
internal static class TestDownloads
{
    public static DownloadService Create(FakeArrClient arr, TimeProvider? time = null, string? file = null, AdminAlerts? alerts = null) =>
        new(
            arr,
            new FakeArrSettings(),
            new FakeDownloadSettings(),
            new DownloadStore(file ?? Path.Combine(Path.GetTempPath(), "wfwp-unused", "downloads.json"), NullLogger<DownloadStore>.Instance),
            time ?? TimeProvider.System,
            NullLogger<DownloadService>.Instance,
            alerts)
        { Pause = TimeSpan.Zero };
}
