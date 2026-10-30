using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MovieItem = MediaBrowser.Controller.Entities.Movies.Movie;
using SeriesItem = MediaBrowser.Controller.Entities.TV.Series;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Visione, preferiti e generi da Jellyfin (spec U §4). Una query sola per serie (gli episodi veri, senza
/// utente) e una sola lettura di <c>GetUserData</c> per utente e item. Gli episodi senza file
/// (<c>IsVirtualItem</c>) non contano: né per "aperto" né per "finito".
/// </summary>
public sealed class JellyfinViewingFacts(
    ILibraryManager libraryManager,
    IUserManager userManager,
    IUserDataManager userDataManager,
    IUserDirectory userDirectory) : IViewingFacts
{
    public ItemViewing? Movie(Guid itemId) =>
        Find(itemId) is Movie movie ? Viewing(movie, [movie], movie.Genres) : null;

    public ItemViewing? Series(Guid seriesId) =>
        Find(seriesId) is Series series ? Viewing(series, Episodes(series.Id), series.Genres) : null;

    public IReadOnlyDictionary<int, ItemViewing> Seasons(Guid seriesId)
    {
        var result = new Dictionary<int, ItemViewing>();
        if (Find(seriesId) is not Series series)
        {
            return result;
        }

        var bySeason = Episodes(series.Id).ToLookup(episode => episode.ParentIndexNumber);
        var seasons = libraryManager.GetItemList(new InternalItemsQuery
        {
            AncestorIds = [series.Id],
            IncludeItemTypes = [BaseItemKind.Season],
        });
        foreach (var season in seasons)
        {
            // Senza numero di stagione non c'è modo di indicarla: la si salta.
            if (season.IndexNumber is { } number)
            {
                // I generi stanno sulla serie, la stagione non li ha.
                result.TryAdd(number, Viewing(season, bySeason[number].ToList(), series.Genres));
            }
        }

        return result;
    }

    public bool IsFavorite(Guid userId, Guid itemId) =>
        userId != Guid.Empty
        && userManager.GetUserById(userId) is { } user
        && Find(itemId) is { } item
        && userDataManager.GetUserData(user, item)?.IsFavorite == true;

    public IReadOnlyList<string> TopGenres(Guid userId, IReadOnlySet<Guid> highlyRated, int count)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return [];
        }

        var titles = new Dictionary<Guid, BaseItem>();
        // Con l'utente nella query, IsPlayed guarda la sua riga "visto".
        foreach (var movie in libraryManager.GetItemList(new InternalItemsQuery(user)
        {
            IncludeItemTypes = [BaseItemKind.Movie],
            IsPlayed = true,
        }))
        {
            titles[movie.Id] = movie;
        }

        var seriesIds = libraryManager.GetItemList(new InternalItemsQuery(user)
        {
            IncludeItemTypes = [BaseItemKind.Episode],
            IsVirtualItem = false,
            IsPlayed = true,
        }).OfType<Episode>().Select(episode => episode.SeriesId);
        foreach (var id in seriesIds.Concat(highlyRated))
        {
            // Un voto alto è di solito su una stagione: il genere è quello della serie.
            var item = Find(id) is Season season ? Find(season.SeriesId) : Find(id);
            if (item is MovieItem or SeriesItem)
            {
                titles[item.Id] = item;
            }
        }

        return titles.Values
            .SelectMany(title => title.Genres)
            .GroupBy(genre => genre, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(group => group.Count())
            .ThenBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Key)
            .Take(count)
            .ToList();
    }

    // Con un id vuoto GetItemById lancia: l'item non c'è e basta.
    private BaseItem? Find(Guid id) => id == Guid.Empty ? null : libraryManager.GetItemById(id);

    private List<BaseItem> Episodes(Guid seriesId) =>
        libraryManager.GetItemList(new InternalItemsQuery
        {
            AncestorIds = [seriesId],
            IncludeItemTypes = [BaseItemKind.Episode],
            IsVirtualItem = false,
        }).ToList();

    private ItemViewing Viewing(BaseItem item, IReadOnlyList<BaseItem> watchable, IEnumerable<string> genres) =>
        new(item.Id, item.DateCreated == default ? null : Utc(item.DateCreated), Usage(watchable), genres.ToList());

    /// <summary>Per ogni utente attivo che ha aperto qualcosa tra gli item: se li ha finiti tutti e l'ultima volta.</summary>
    private List<UserUsage> Usage(IReadOnlyList<BaseItem> watchable)
    {
        var usage = new List<UserUsage>();
        if (watchable.Count == 0)
        {
            return usage;
        }

        foreach (var (user, name) in ActiveUsers())
        {
            var data = watchable.Select(item => userDataManager.GetUserData(user, item)).ToList();
            if (!data.Any(d => d is { Played: true } or { PlaybackPositionTicks: > 0 }))
            {
                continue;
            }

            var last = data.Max(d => d?.LastPlayedDate);
            usage.Add(new UserUsage(user.Id, name, true, data.All(d => d?.Played == true), last is { } date ? Utc(date) : null));
        }

        return usage;
    }

    private List<(User User, string Name)> ActiveUsers() =>
        userDirectory.GetUsers()
            .Where(u => u.Enabled && userManager.GetUserById(u.Id) is not null)
            .Select(u => (userManager.GetUserById(u.Id)!, u.Name))
            .ToList();

    // Jellyfin salva le date in UTC, a volte senza dirlo (Kind Unspecified).
    private static DateTimeOffset Utc(DateTime date) => new(DateTime.SpecifyKind(date, DateTimeKind.Utc));
}
