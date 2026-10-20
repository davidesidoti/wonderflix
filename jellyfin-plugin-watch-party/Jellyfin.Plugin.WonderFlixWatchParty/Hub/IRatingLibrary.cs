namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un film o una stagione che si può votare; DisplayTitle "Il Padrino (1972)" o "Breaking Bad · Stagione 2".</summary>
public sealed record RatedTitle(Guid Id, bool IsSeason, string DisplayTitle);

/// <summary>Le domande dei voti alla libreria (spec Q §12). Possono lanciare: chi chiama le protegge.</summary>
public interface IRatingLibrary
{
    /// <summary>Il film o la stagione (con numero); null se non c'è o è un altro tipo.</summary>
    RatedTitle? FindRated(Guid itemId);

    /// <summary>Cosa si vota a fine party: il film stesso, la stagione per l'ultimo episodio della stagione; null altrimenti.</summary>
    Guid? RoundTarget(Guid itemId);

    /// <summary>L'utente ha visto il titolo: il film Played, la stagione senza episodi veri non visti.</summary>
    bool HasWatched(Guid userId, RatedTitle title);
}
