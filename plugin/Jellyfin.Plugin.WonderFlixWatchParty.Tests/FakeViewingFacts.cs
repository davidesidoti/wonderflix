using Jellyfin.Plugin.WonderFlixWatchParty.Space;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Visione, preferiti e generi in memoria; quello che non è nei dizionari non c'è.</summary>
internal sealed class FakeViewingFacts : IViewingFacts
{
    public Dictionary<Guid, ItemViewing> Movies { get; } = [];

    public Dictionary<Guid, ItemViewing> SeriesById { get; } = [];

    public Dictionary<Guid, IReadOnlyDictionary<int, ItemViewing>> SeasonsBySeries { get; } = [];

    /// <summary>Le coppie (utente, item) dei preferiti.</summary>
    public HashSet<(Guid UserId, Guid ItemId)> Favorites { get; } = [];

    /// <summary>Quello che risponde TopGenres, per qualsiasi utente.</summary>
    public IReadOnlyList<string> TopGenresResult { get; set; } = [];

    public ItemViewing? Movie(Guid itemId) => Movies.GetValueOrDefault(itemId);

    public ItemViewing? Series(Guid seriesId) => SeriesById.GetValueOrDefault(seriesId);

    public IReadOnlyDictionary<int, ItemViewing> Seasons(Guid seriesId) =>
        SeasonsBySeries.GetValueOrDefault(seriesId) ?? new Dictionary<int, ItemViewing>();

    public bool IsFavorite(Guid userId, Guid itemId) => Favorites.Contains((userId, itemId));

    public IReadOnlyList<string> TopGenres(Guid userId, IReadOnlySet<Guid> highlyRated, int count) =>
        TopGenresResult.Take(count).ToList();
}
