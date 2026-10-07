namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Una collezione (BoxSet) come la vede un utente, con i titoli che può vedere (spec K §7.1).</summary>
public sealed record CollectionInfo(
    Guid Id,
    string Name,
    string SortName,
    string? PrimaryImageTag,
    DateTime DateCreated,
    IReadOnlyList<Guid> ItemIds);

/// <summary>Le collezioni di Jellyfin (adattatore di ICollectionManager, IUserManager e IImageProcessor).</summary>
public interface ICollectionDirectory
{
    /// <summary>
    /// Le collezioni che l'utente vede, ognuna con i titoli collegati che può
    /// vedere; vuoto se l'utente o la cartella delle collezioni non ci sono.
    /// </summary>
    Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId);
}
