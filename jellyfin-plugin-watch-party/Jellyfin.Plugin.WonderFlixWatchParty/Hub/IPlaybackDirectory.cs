namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un film o un episodio in riproduzione (spec O §6.2). TitleId è quello che
/// si registra: il film, o la serie dell'episodio; null per un episodio
/// senza serie (piano 21a, decisione 7).
/// </summary>
public sealed record PlayingTitle(
    Guid ItemId, string Name, Guid? TitleId, Guid? SeriesId, string? SeriesName, int? Season, int? Episode);

/// <summary>
/// Una riproduzione in una sessione WonderFlix: la posizione (Jellyfin la fa
/// avanzare da sé ogni secondo, piano 21a decisione 4) e l'ultimo resoconto
/// dell'app.
/// </summary>
public sealed record AppPlayback(
    string SessionId, Guid UserId, PlayingTitle Item, long PositionTicks, DateTimeOffset LastCheckIn);

/// <summary>
/// Un resoconto vero di una sessione WonderFlix (spec O §6.3–6.4), da un
/// evento di riproduzione: il film o la serie (null per un episodio senza
/// serie), la posizione e se è arrivato alla fine.
/// </summary>
public sealed record PlaybackReport(string SessionId, Guid UserId, Guid? TitleId, long PositionTicks, bool Completed);

/// <summary>Le riproduzioni del server (adattatore di ISessionManager).</summary>
public interface IPlaybackDirectory
{
    /// <summary>I film e gli episodi in riproduzione nelle sessioni WonderFlix con un utente.</summary>
    IReadOnlyList<AppPlayback> GetAppPlayback();
}
