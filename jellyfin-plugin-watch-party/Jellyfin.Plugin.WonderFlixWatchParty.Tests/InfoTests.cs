using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

// Provvisorio: nel Task 6 il controller cambia costruttore e il test passa in
// WatchPartyControllerTests.
public class InfoTests
{
    [Fact]
    public void InfoReportsVersionAndProtocol()
    {
        var controller = new WatchPartyController(null!, null!);
        var info = controller.GetInfo().Value!;
        Assert.Equal("1.0.0", info.Version);
        Assert.Equal(1, info.Protocol);
    }
}
