using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinMatchLibraryTests
{
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly List<InternalItemsQuery> _queries = [];
    private readonly Movie _dune = new() { Id = Guid.NewGuid(), Name = "Dune", RunTimeTicks = TimeSpan.FromMinutes(155).Ticks };
    private readonly Series _bear = new() { Id = Guid.NewGuid(), Name = "The Bear" };

    private JellyfinMatchLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemList"] = args =>
        {
            var query = (InternalItemsQuery)args[0]!;
            _queries.Add(query);
            return query.IncludeItemTypes.SequenceEqual([BaseItemKind.Movie])
                ? new List<BaseItem> { _dune }
                : new List<BaseItem> { _bear };
        };
        var (userManager, users) = InterfaceStub<IUserManager>.Create();
        users.Handlers["GetUserById"] = args => (Guid)args[0]! == _luigi.Id ? _luigi : null;
        return new JellyfinMatchLibrary(libraryManager, userManager);
    }

    [Fact]
    public void OneRandomQueryPerTypeOnTheUsersLibrary()
    {
        var exclude = new[] { Guid.NewGuid() };

        var candidates = Library().Candidates(_luigi.Id, new MatchFilters(true, true, null, "Drama"), exclude, 300);

        Assert.Equal(2, _queries.Count);
        Assert.Equal(new[] { BaseItemKind.Movie }, _queries[0].IncludeItemTypes);
        Assert.Equal(new[] { BaseItemKind.Series }, _queries[1].IncludeItemTypes);
        Assert.All(_queries, query =>
        {
            Assert.Same(_luigi, query.User);
            Assert.True(query.Recursive);
            Assert.False(query.IsPlayed);
            Assert.False(query.IsVirtualItem);
            Assert.Equal(new[] { "Drama" }, query.Genres);
            Assert.Equal(exclude, query.ExcludeItemIds);
            Assert.Equal(new[] { (ItemSortBy.Random, SortOrder.Ascending) }, query.OrderBy);
            Assert.Equal(150, query.Limit);
        });
        Assert.Equal(2, candidates.Count);
        Assert.Contains(new MatchCandidate(_dune.Id, true, TimeSpan.FromMinutes(155).Ticks), candidates);
        Assert.Contains(new MatchCandidate(_bear.Id, false, null), candidates);
    }

    [Fact]
    public void OneTypeGetsTheWholeLimitAndNoGenreMeansAll()
    {
        Library().Candidates(_luigi.Id, new MatchFilters(true, false, TimeSpan.FromMinutes(90), null), [], 300);

        var query = Assert.Single(_queries);
        Assert.Equal(new[] { BaseItemKind.Movie }, query.IncludeItemTypes);
        Assert.Equal(300, query.Limit);
        Assert.Empty(query.Genres);
    }

    [Fact]
    public void TheQueryCarriesTheUsersContentLimits()
    {
        // Il costruttore con l'utente mette i suoi limiti d'età nella query: con "User = …" mancherebbero.
        _luigi.MaxParentalRatingScore = 12;

        Library().Candidates(_luigi.Id, new MatchFilters(true, false, null, null), [], 300);

        Assert.NotNull(Assert.Single(_queries).MaxParentalRating);
    }

    [Fact]
    public void AnUnknownUserGetsNothing()
    {
        Assert.Empty(Library().Candidates(Guid.NewGuid(), new MatchFilters(true, true, null, null), [], 300));
        Assert.Empty(Library().Candidates(Guid.Empty, new MatchFilters(true, true, null, null), [], 300));
        Assert.Empty(_queries);
    }
}
