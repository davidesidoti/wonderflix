using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il raccoglitore dei nuovi titoli dei test, sul server finto.</summary>
internal static class TestNewTitles
{
    public static NewTitlesCollector Create(FakeServer server, InboxService inbox, TimeProvider time) =>
        new(server, server, server, inbox, server, time, NullLogger<NewTitlesCollector>.Instance);
}
