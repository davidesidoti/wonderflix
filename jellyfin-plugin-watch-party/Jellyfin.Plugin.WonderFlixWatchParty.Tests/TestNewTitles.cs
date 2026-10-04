using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il raccoglitore dei nuovi titoli dei test, sul server finto.</summary>
internal static class TestNewTitles
{
    public static NewTitlesCollector Create(
        FakeServer server, InboxService inbox, TimeProvider time, ILogger<NewTitlesCollector>? logger = null) =>
        new(server, server, server, inbox, server, time, logger ?? NullLogger<NewTitlesCollector>.Instance);
}
