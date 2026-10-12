using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un film o una serie che si può consigliare (spec N §6.2).</summary>
public sealed record RecommendableItem(Guid Id, string Name, int? Year)
{
    /// <summary>Il titolo della voce nella cassetta: "Dune (2021)", o solo il nome senza anno.</summary>
    public string DisplayTitle =>
        Year is { } year ? string.Create(CultureInfo.InvariantCulture, $"{Name} ({year})") : Name;
}

/// <summary>La libreria come serve ai consigli (adattatore di ILibraryManager, IUserManager e IUserDataManager).</summary>
public interface IRecommendationLibrary
{
    /// <summary>Il film o la serie; null se non c'è o è un altro tipo (episodio, stagione, collezione…).</summary>
    RecommendableItem? GetTitle(Guid itemId);

    /// <summary>
    /// Quando l'utente ha guardato il titolo l'ultima volta (spec N §6.3):
    /// per un film la sua ultima visione, per una serie quella dell'episodio
    /// visto più di recente. Null se mai, o se utente o titolo non ci sono.
    /// </summary>
    DateTimeOffset? LastWatched(Guid userId, Guid itemId);
}
