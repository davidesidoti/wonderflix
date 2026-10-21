using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinReportLibraryTests
{
    private readonly Guid _series = Guid.NewGuid();
    private readonly Dictionary<Guid, BaseItem> _items = [];

    private JellyfinReportLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => _items.GetValueOrDefault((Guid)args[0]!);
        return new JellyfinReportLibrary(libraryManager);
    }

    private T Add<T>(T item) where T : BaseItem
    {
        item.Id = Guid.NewGuid();
        _items[item.Id] = item;
        return item;
    }

    [Fact]
    public void ItemsMapToTheirLevel()
    {
        var library = Library();
        var movie = Add(new Movie { Name = "Dune" });
        var series = Add(new Series { Name = "Breaking Bad" });
        var season = Add(new Season { Name = "Season 2", SeriesId = _series, SeriesName = "Breaking Bad", IndexNumber = 2 });
        var episode = Add(new Episode
        {
            SeriesId = _series,
            SeriesName = "Breaking Bad",
            ParentIndexNumber = 2,
            IndexNumber = 3,
            Name = "Bit by a Dead Bee",
        });

        Assert.Equal(new ReportedItem(movie.Id, "Movie", "Dune", movie.Id, "Dune", null, null), library.Find(movie.Id));
        Assert.Equal(new ReportedItem(series.Id, "Series", "Breaking Bad", series.Id, "Breaking Bad", null, null), library.Find(series.Id));
        Assert.Equal(new ReportedItem(season.Id, "Season", "Season 2", _series, "Breaking Bad", 2, null), library.Find(season.Id));
        Assert.Equal(
            new ReportedItem(episode.Id, "Episode", "Bit by a Dead Bee", _series, "Breaking Bad", 2, 3),
            library.Find(episode.Id));
    }

    [Fact]
    public void OtherItemsAreNull()
    {
        var library = Library();

        Assert.Null(library.Find(Add(new BoxSet()).Id));
        Assert.Null(library.Find(Guid.NewGuid()));
        Assert.Null(library.Find(Guid.Empty));
        Assert.Null(library.Find(Add(new Season { IndexNumber = 1 }).Id));
        Assert.Null(library.Find(Add(new Episode { ParentIndexNumber = 1, IndexNumber = 1 }).Id));
    }

    [Fact]
    public void MissingNamesBecomeEmpty()
    {
        var movie = Add(new Movie());

        Assert.Equal(new ReportedItem(movie.Id, "Movie", string.Empty, movie.Id, string.Empty, null, null), Library().Find(movie.Id));
    }
}
