namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Un film o una serie della libreria, con quel che serve a trovarne il trailer. <paramref name="MediaType"/> è "movie" o "tv".</summary>
public sealed record TrailerItem(string MediaType, int? TmdbId, IReadOnlyList<string> RemoteTrailerUrls);

/// <summary>La libreria vista dal risolutore dei trailer.</summary>
public interface ITrailerLibrary
{
    /// <summary>L'elemento; null se non esiste, non è un film o una serie, o l'utente non lo vede.</summary>
    TrailerItem? Find(Guid userId, Guid itemId);
}
