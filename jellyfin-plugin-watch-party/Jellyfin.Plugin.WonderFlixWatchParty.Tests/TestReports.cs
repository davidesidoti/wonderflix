using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Le segnalazioni dei test: server finto, file in una cartella temporanea.</summary>
internal static class TestReports
{
    public static ReportService Create(
        FakeServer server, TempFolder folder, TimeProvider time, InboxService inbox, ILogger<ReportService>? logger = null) =>
        new(
            new ReportStore(folder.ReportsFile, NullLogger<ReportStore>.Instance),
            server, server, server, server, inbox, time, logger ?? NullLogger<ReportService>.Instance);
}
