using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinRatingLibraryTests
{
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly Guid _series = Guid.NewGuid();
    private readonly Guid _season = Guid.NewGuid();
    private readonly Dictionary<Guid, BaseItem> _items = [];
    private readonly List<InternalItemsQuery> _queries = [];
    private List<BaseItem> _found = [];
    private bool? _played;

    private JellyfinRatingLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => _items.GetValueOrDefault((Guid)args[0]!);
        library.Handlers["GetItemList"] = args =>
        {
            _queries.Add((InternalItemsQuery)args[0]!);
            return _found;
        };
        var (userManager, users) = InterfaceStub<IUserManager>.Create();
        users.Handlers["GetUserById"] = args => (Guid)args[0]! == _luigi.Id ? _luigi : null;
        var (userDataManager, userData) = InterfaceStub<IUserDataManager>.Create();
        userData.Handlers["GetUserData"] = _ => _played is { } played ? new UserItemData { Key = "k", Played = played } : null;
        return new JellyfinRatingLibrary(libraryManager, userManager, userDataManager);
    }

    private T Add<T>(T item) where T : BaseItem
    {
        item.Id = Guid.NewGuid();
        _items[item.Id] = item;
        return item;
    }

    [Fact]
    public void TheLastEpisodeOfASeasonGivesTheSeason()
    {
        // S02E07-E08, doppio; nessun episodio dopo.
        var episode = Add(new Episode { SeriesId = _series, SeasonId = _season, ParentIndexNumber = 2, IndexNumber = 7, IndexNumberEnd = 8 });

        Assert.Equal(_season, Library().RoundTarget(episode.Id));
        var query = Assert.Single(_queries);
        Assert.Equal(new[] { _series }, query.AncestorIds);
        Assert.Equal(new[] { BaseItemKind.Episode }, query.IncludeItemTypes);
        Assert.Equal(2, query.ParentIndexNumber);
        Assert.Equal(9, query.MinIndexNumber);
        Assert.False(query.IsVirtualItem);
        Assert.Null(query.User);
        Assert.Equal(1, query.Limit);
    }

    [Fact]
    public void AMiddleEpisodeGivesNothing()
    {
        var episode = Add(new Episode { SeriesId = _series, SeasonId = _season, ParentIndexNumber = 2, IndexNumber = 3 });
        _found = [Add(new Episode { SeriesId = _series, ParentIndexNumber = 2, IndexNumber = 4 })];

        Assert.Null(Library().RoundTarget(episode.Id));
        Assert.Equal(4, Assert.Single(_queries).MinIndexNumber);
    }

    [Fact]
    public void AMovieIsItsOwnTargetAndOtherTypesNone()
    {
        var movie = Add(new Movie());
        var library = Library();

        Assert.Equal(movie.Id, library.RoundTarget(movie.Id));
        Assert.Null(library.RoundTarget(Add(new Series()).Id));
        Assert.Null(library.RoundTarget(Add(new Season()).Id));
        Assert.Null(library.RoundTarget(Guid.NewGuid()));
        Assert.Null(library.RoundTarget(Guid.Empty));
        Assert.Null(library.RoundTarget(Add(new Episode { SeriesId = _series, SeasonId = _season, ParentIndexNumber = 2 }).Id));
        Assert.Null(library.RoundTarget(Add(new Episode { SeriesId = _series, ParentIndexNumber = 2, IndexNumber = 1 }).Id));
        Assert.Empty(_queries);
    }

    [Fact]
    public void RatedTitlesHaveTheirDisplayNames()
    {
        var library = Library();
        var movie = Add(new Movie { Name = "Il Padrino", ProductionYear = 1972 });
        var noYear = Add(new Movie { Name = "Il Padrino" });
        var second = Add(new Season { SeriesName = "Breaking Bad", IndexNumber = 2 });
        var specials = Add(new Season { SeriesName = "Breaking Bad", IndexNumber = 0 });

        Assert.Equal(new RatedTitle(movie.Id, false, "Il Padrino (1972)"), library.FindRated(movie.Id));
        Assert.Equal("Il Padrino", library.FindRated(noYear.Id)!.DisplayTitle);
        Assert.Equal(new RatedTitle(second.Id, true, "Breaking Bad · Stagione 2"), library.FindRated(second.Id));
        Assert.Equal("Breaking Bad · Speciali", library.FindRated(specials.Id)!.DisplayTitle);
        Assert.Null(library.FindRated(Add(new Season { SeriesName = "Breaking Bad" }).Id));
        Assert.Null(library.FindRated(Add(new Episode()).Id));
        Assert.Null(library.FindRated(Add(new Series()).Id));
        Assert.Null(library.FindRated(Guid.NewGuid()));
        Assert.Null(library.FindRated(Guid.Empty));
    }

    [Fact]
    public void AMovieIsWatchedWhenPlayed()
    {
        var movie = Add(new Movie { Name = "Dune" });
        var title = new RatedTitle(movie.Id, false, "Dune");
        var library = Library();

        _played = true;
        Assert.True(library.HasWatched(_luigi.Id, title));
        _played = false;
        Assert.False(library.HasWatched(_luigi.Id, title));
        _played = null;
        Assert.False(library.HasWatched(_luigi.Id, title));
        _played = true;
        Assert.False(library.HasWatched(Guid.NewGuid(), title));
        Assert.Empty(_queries);
    }

    [Fact]
    public void ASeasonIsWatchedWhenNoRealEpisodeIsUnplayed()
    {
        var season = Add(new Season { SeriesId = _series, SeriesName = "Breaking Bad", IndexNumber = 2 });
        var title = new RatedTitle(season.Id, true, "Breaking Bad · Stagione 2");

        Assert.True(Library().HasWatched(_luigi.Id, title));
        var query = Assert.Single(_queries);
        Assert.Same(_luigi, query.User);
        Assert.False(query.IsPlayed);
        Assert.False(query.IsVirtualItem);
        Assert.Equal(2, query.ParentIndexNumber);
        Assert.Equal(new[] { _series }, query.AncestorIds);
        Assert.Equal(new[] { BaseItemKind.Episode }, query.IncludeItemTypes);
        Assert.Equal(1, query.Limit);

        _found = [Add(new Episode())];
        Assert.False(Library().HasWatched(_luigi.Id, title));
    }

    [Fact]
    public void TheSeasonQueryCarriesTheUsersContentLimits()
    {
        _luigi.MaxParentalRatingScore = 12;
        var season = Add(new Season { SeriesId = _series, IndexNumber = 1 });

        Library().HasWatched(_luigi.Id, new RatedTitle(season.Id, true, "x"));

        Assert.NotNull(Assert.Single(_queries).MaxParentalRating);
    }
}
