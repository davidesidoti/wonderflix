namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>
/// La visione di un film, di una serie o di una stagione: quando è arrivato, chi l'ha aperto
/// (solo utenti attivi, e solo chi l'ha aperto) e i generi (spec U §4).
/// </summary>
public sealed record ItemViewing(Guid ItemId, DateTimeOffset? Added, IReadOnlyList<UserUsage> Usage, IReadOnlyList<string> Genres);

/// <summary>
/// Cosa sa Jellyfin di chi guarda cosa (spec U §4). "Aperto" è <c>Played</c> o
/// <c>PlaybackPositionTicks &gt; 0</c> sul film o su un episodio; "finito" è <c>Played</c> sul film o su
/// tutti gli episodi con file (decisione 7 del piano 30a).
/// </summary>
public interface IViewingFacts
{
    /// <summary>null se il film non c'è (più).</summary>
    ItemViewing? Movie(Guid itemId);

    /// <summary>L'unione degli episodi; null se la serie non c'è (più).</summary>
    ItemViewing? Series(Guid seriesId);

    /// <summary>Le stagioni della serie, per numero di stagione; <c>ItemId</c> è quello della stagione.</summary>
    IReadOnlyDictionary<int, ItemViewing> Seasons(Guid seriesId);

    /// <summary>Se l'utente ha tra i preferiti il film, la serie o la stagione.</summary>
    bool IsFavorite(Guid userId, Guid itemId);

    /// <summary>
    /// I generi che l'utente guarda di più: quelli dei film e delle serie visti (una serie conta se ha almeno
    /// un episodio visto) o in <paramref name="highlyRated"/>, dal più frequente, a parità in ordine alfabetico.
    /// </summary>
    IReadOnlyList<string> TopGenres(Guid userId, IReadOnlySet<Guid> highlyRated, int count);
}
