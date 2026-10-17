namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un titolo candidato alla pila: un film (con la durata, se nota) o una serie.</summary>
public sealed record MatchCandidate(Guid Id, bool IsMovie, long? RunTimeTicks, float? Rating = null);

/// <summary>La libreria come serve al match (adattatore di ILibraryManager e IUserManager).</summary>
public interface IMatchLibrary
{
    /// <summary>
    /// Film e serie a caso della libreria che userId può vedere, del tipo e
    /// del genere dei filtri, mai visti da lui, senza gli exclude; al
    /// massimo limit. La durata non la filtra: la controlla chi chiama.
    /// </summary>
    IReadOnlyList<MatchCandidate> Candidates(Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit);
}
