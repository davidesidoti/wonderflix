using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinRecommendationLibraryTests
{
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly Dictionary<Guid, BaseItem> _items = [];
    private readonly Dictionary<Guid, DateTime?> _played = [];
    private readonly List<InternalItemsQuery> _queries = [];
    private BaseItem? _latestEpisode;

    private JellyfinRecommendationLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => _items.GetValueOrDefault((Guid)args[0]!);
        library.Handlers["GetItemList"] = args =>
        {
            _queries.Add((InternalItemsQuery)args[0]!);
            return _latestEpisode is null ? new List<BaseItem>() : new List<BaseItem> { _latestEpisode };
        };
        var (userManager, users) = InterfaceStub<IUserManager>.Create();
        users.Handlers["GetUserById"] = args => (Guid)args[0]! == _luigi.Id ? _luigi : null;
        var (userDataManager, userData) = InterfaceStub<IUserDataManager>.Create();
        userData.Handlers["GetUserData"] = args =>
            _played.TryGetValue(((BaseItem)args[1]!).Id, out var date) ? new UserItemData { Key = "k", LastPlayedDate = date } : null;
        return new JellyfinRecommendationLibrary(libraryManager, userManager, userDataManager);
    }

    private T Add<T>(T item)
        where T : BaseItem
    {
        _items[item.Id] = item;
        return item;
    }

    [Fact]
    public void OnlyMoviesAndSeriesCanBeRecommended()
    {
        var movie = Add(new Movie { Id = Guid.NewGuid(), Name = "Dune", ProductionYear = 2021 });
        var series = Add(new Series { Id = Guid.NewGuid(), Name = "The Bear" });
        var episode = Add(new Episode { Id = Guid.NewGuid(), Name = "Pilot" });
        var library = Library();

        Assert.Equal(("Dune", 2021), (library.GetTitle(movie.Id)!.Name, library.GetTitle(movie.Id)!.Year));
        Assert.Equal("The Bear", library.GetTitle(series.Id)!.Name);
        Assert.Null(library.GetTitle(series.Id)!.Year);
        Assert.Null(library.GetTitle(episode.Id));
        Assert.Null(library.GetTitle(Guid.NewGuid()));
        Assert.Null(library.GetTitle(Guid.Empty));
    }

    [Fact]
    public void AMovieIsWatchedWhenItsLastPlayedDateIs()
    {
        var movie = Add(new Movie { Id = Guid.NewGuid(), Name = "Dune" });
        var library = Library();
        Assert.Null(library.LastWatched(_luigi.Id, movie.Id));

        _played[movie.Id] = new DateTime(2026, 10, 12, 21, 0, 0, DateTimeKind.Unspecified);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 21, 0, 0, TimeSpan.Zero), library.LastWatched(_luigi.Id, movie.Id));

        // Utente o titolo che non ci sono.
        Assert.Null(library.LastWatched(Guid.NewGuid(), movie.Id));
        Assert.Null(library.LastWatched(_luigi.Id, Guid.NewGuid()));
        Assert.Null(library.LastWatched(Guid.Empty, Guid.Empty));
    }

    [Fact]
    public void ASeriesIsWatchedWhenItsLatestEpisodeIs()
    {
        var series = Add(new Series { Id = Guid.NewGuid(), Name = "The Bear" });
        var library = Library();
        Assert.Null(library.LastWatched(_luigi.Id, series.Id));

        _latestEpisode = new Episode { Id = Guid.NewGuid() };
        _played[_latestEpisode.Id] = new DateTime(2026, 10, 12, 22, 0, 0, DateTimeKind.Utc);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 22, 0, 0, TimeSpan.Zero), library.LastWatched(_luigi.Id, series.Id));

        // Una domanda sola: gli episodi veri della serie, dall'ultimo visto dall'utente.
        var query = _queries[^1];
        Assert.Same(_luigi, query.User);
        Assert.Equal(new[] { series.Id }, query.AncestorIds);
        Assert.Equal(new[] { BaseItemKind.Episode }, query.IncludeItemTypes);
        Assert.False(query.IsVirtualItem);
        Assert.Equal(1, query.Limit);
        Assert.Equal((ItemSortBy.DatePlayed, SortOrder.Descending), Assert.Single(query.OrderBy));
    }
}
