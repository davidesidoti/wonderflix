using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NewTitlesAdapterTests
{
    private static Movie Movie(string path = "/media/film/dune.mkv") =>
        new() { Id = Guid.NewGuid(), Name = "Dune", Path = path, ProductionYear = 2024 };

    [Fact]
    public void OnlyRealMoviesAndEpisodesAreTitles()
    {
        Assert.True(NewTitleRules.IsRealTitle(Movie()));
        Assert.True(NewTitleRules.IsRealTitle(new Episode { Id = Guid.NewGuid(), Path = "/media/tv/e1.mkv" }));
        Assert.False(NewTitleRules.IsRealTitle(null));
        // Il segnaposto "mancante" del plugin TVDB.
        Assert.False(NewTitleRules.IsRealTitle(new Episode { Id = Guid.NewGuid(), IsVirtualItem = true }));
        Assert.False(NewTitleRules.IsRealTitle(Movie(path: string.Empty)));
        Assert.False(NewTitleRules.IsRealTitle(
            new Movie { Id = Guid.NewGuid(), Path = "/x.mkv", ExtraType = ExtraType.BehindTheScenes }));
        Assert.False(NewTitleRules.IsRealTitle(new Movie { Id = Guid.NewGuid(), Path = "/x.mkv", OwnerId = Guid.NewGuid() }));
        Assert.False(NewTitleRules.IsRealTitle(new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear" }));
        Assert.False(NewTitleRules.IsRealTitle(new Trailer { Id = Guid.NewGuid(), Path = "/media/film/trailer.mkv" }));
    }

    [Fact]
    public void RemovedSeriesAndSeasonFoldersGiveTheSeriesKey()
    {
        Assert.True(NewTitleRules.TryGetRemovedContainer(
            new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear", PresentationUniqueKey = "bear-key" },
            out var key,
            out var season));
        Assert.Equal("bear-key", key);
        Assert.Null(season);

        Assert.True(NewTitleRules.TryGetRemovedContainer(
            new Season { Id = Guid.NewGuid(), Path = "/media/tv/The Bear/Season 2", SeriesPresentationUniqueKey = "bear-key", IndexNumber = 2 },
            out key,
            out season));
        Assert.Equal("bear-key", key);
        Assert.Equal(2, season);

        // Virtuale, senza cartella, senza chiave (anche cercando la serie), o non una serie né una stagione.
        Assert.False(NewTitleRules.TryGetRemovedContainer(
            new Season { Id = Guid.NewGuid(), Path = "/media/tv/x", IsVirtualItem = true, SeriesPresentationUniqueKey = "bear-key" },
            out _,
            out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(
            new Season { Id = Guid.NewGuid(), SeriesPresentationUniqueKey = "bear-key", IndexNumber = 1 }, out _, out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(
            new Season { Id = Guid.NewGuid(), Path = "/media/tv/x/Season 1", IndexNumber = 1 }, out _, out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(
            new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear" }, out _, out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(Movie(), out _, out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(
            new Episode { Id = Guid.NewGuid(), Path = "/media/tv/e1.mkv", SeriesPresentationUniqueKey = "bear-key" }, out _, out _));
        Assert.False(NewTitleRules.TryGetRemovedContainer(null, out _, out _));
    }

    [Fact]
    public void ExternalKeysAreTmdbImdbAndTvdb()
    {
        var movie = Movie();
        movie.ProviderIds["Tmdb"] = "438631";
        movie.ProviderIds["Imdb"] = " tt1160419 ";
        movie.ProviderIds["Tvdb"] = string.Empty;
        movie.ProviderIds["MusicBrainzAlbum"] = "x";

        Assert.Equal(new[] { "Tmdb:438631", "Imdb:tt1160419" }, NewTitleRules.ExternalKeys(movie));
    }

    [Fact]
    public void TitlesAreReReadFromTheLibrary()
    {
        var movie = Movie();
        movie.ProviderIds["Tmdb"] = "438631";
        var seriesId = Guid.NewGuid();
        var episode = new Episode
        {
            Id = Guid.NewGuid(),
            Name = "Pilot",
            Path = "/media/tv/e1.mkv",
            SeriesId = seriesId,
            SeriesName = "The Bear",
            SeriesPresentationUniqueKey = "bear-key",
            ParentIndexNumber = 3,
            IndexNumber = 1,
            DateLastRefreshed = new DateTime(2026, 10, 4, 0, 0, 0, DateTimeKind.Utc),
        };
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        stub.Handlers["GetItemById"] = args =>
            (Guid)args[0]! == movie.Id ? movie : (Guid)args[0]! == episode.Id ? episode : null;
        var titles = new JellyfinLibraryTitles(library, InterfaceStub<IUserManager>.Create().Proxy);

        var film = titles.Get(movie.Id)!;
        Assert.True(film.IsMovie);
        Assert.Equal("Dune", film.Name);
        Assert.Equal(2024, film.Year);
        Assert.Equal(new[] { "Tmdb:438631" }, film.ExternalKeys);
        Assert.False(film.Refreshed, "metadati mai aggiornati: DateLastRefreshed vuota");
        var ep = titles.Get(episode.Id)!;
        Assert.False(ep.IsMovie);
        Assert.Equal(seriesId, ep.SeriesId);
        Assert.Equal("The Bear", ep.SeriesName);
        Assert.Equal("bear-key", ep.SeriesKey);
        Assert.Equal(3, ep.Season);
        Assert.Equal(1, ep.Episode);
        Assert.True(ep.Refreshed);
        Assert.Null(titles.Get(Guid.NewGuid()));
        Assert.Null(titles.Get(Guid.Empty));
    }

    [Fact]
    public void FollowingIsAFavouriteOrAnotherEpisodePlayedOrStarted()
    {
        var user = new User("mario", "provider", "reset");
        var seriesId = Guid.NewGuid();
        var newEpisode = Guid.NewGuid();
        var (users, usersStub) = InterfaceStub<IUserManager>.Create();
        usersStub.Handlers["GetUserById"] = args => (Guid)args[0]! == user.Id ? user : null;
        var queries = new List<InternalItemsQuery>();
        var answers = new Queue<int>();
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        stub.Handlers["GetCount"] = args =>
        {
            queries.Add((InternalItemsQuery)args[0]!);
            return answers.Dequeue();
        };
        var titles = new JellyfinLibraryTitles(library, users);

        // Preferita: basta la prima domanda.
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        var favourite = Assert.Single(queries);
        Assert.Equal(new[] { seriesId }, favourite.ItemIds);
        Assert.True(favourite.IsFavorite);

        // Un altro episodio visto.
        queries.Clear();
        answers.Enqueue(0);
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        var played = queries[1];
        Assert.Equal("bear-key", played.SeriesPresentationUniqueKey);
        Assert.Equal(new[] { BaseItemKind.Episode }, played.IncludeItemTypes);
        Assert.Equal(new[] { newEpisode }, played.ExcludeItemIds);
        Assert.True(played.IsPlayed);
        Assert.False(played.IsVirtualItem);

        // Un altro episodio iniziato.
        queries.Clear();
        answers.Enqueue(0);
        answers.Enqueue(0);
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        Assert.True(queries[2].IsResumable);

        // Niente.
        answers.Enqueue(0);
        answers.Enqueue(0);
        answers.Enqueue(0);
        Assert.False(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));

        // Senza la chiave della serie solo la preferita; utente sconosciuto: no.
        queries.Clear();
        answers.Enqueue(0);
        Assert.False(titles.FollowsSeries(user.Id, seriesId, string.Empty, [newEpisode]));
        Assert.Single(queries);
        Assert.False(titles.FollowsSeries(Guid.NewGuid(), seriesId, "bear-key", [newEpisode]));
    }
}
