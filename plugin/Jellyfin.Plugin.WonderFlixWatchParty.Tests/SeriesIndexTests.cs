using Jellyfin.Data.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeriesIndexTests
{
    [Fact]
    public void TheIndexReadsEverySeriesWithItsExternalIds()
    {
        // Id fissi, con "The Bear" dopo "Senza id": l'ordine in cui Jellyfin le
        // restituisce non è quello per id, e il test lo vede.
        var bear = new Series { Id = new Guid("00000000-0000-0000-0000-000000000002"), Name = "The Bear" };
        bear.ProviderIds["Tvdb"] = "136311";
        bear.ProviderIds["Tmdb"] = " 136315 ";
        bear.ProviderIds["Imdb"] = "tt14452776";
        var bare = new Series { Id = new Guid("00000000-0000-0000-0000-000000000001"), Name = "Senza id" };
        bare.ProviderIds["Tvdb"] = " ";
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        InternalItemsQuery? asked = null;
        stub.Handlers["GetItemList"] = args =>
        {
            asked = (InternalItemsQuery)args[0]!;
            return new List<BaseItem> { bear, bare };
        };

        var series = new JellyfinSeriesIndex(library).GetSeries();

        Assert.Equal(new[] { BaseItemKind.Series }, asked!.IncludeItemTypes);
        Assert.False(asked.IsVirtualItem);
        Assert.Equal(
            new[]
            {
                new LibrarySeries(bear.Id, "136311", "136315", "tt14452776"),
                new LibrarySeries(bare.Id, null, null, null),
            }.OrderBy(s => s.Id),
            series);
    }
}
