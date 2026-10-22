namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un utente con il tag della sua immagine (spec K §7.2); null senza immagine.</summary>
public sealed record UserAvatarInfo(Guid Id, string Name, string? ImageTag);

/// <summary>Le immagini degli utenti (adattatore di IUserManager e IImageProcessor).</summary>
public interface IUserAvatars
{
    /// <summary>
    /// Gli utenti attivi con uno degli id o dei nomi chiesti (i nomi senza
    /// badare alle maiuscole), ognuno una volta sola; gli altri mancano.
    /// </summary>
    IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names);
}
