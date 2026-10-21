namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un titolo che si può segnalare (spec R §6.2). Type: Movie, Series, Season o Episode.
/// TitleId e TitleName: il film o la serie da aprire; SeasonNumber per stagioni ed episodi,
/// EpisodeNumber per gli episodi.
/// </summary>
public sealed record ReportedItem(
    Guid Id, string Type, string Name, Guid TitleId, string TitleName, int? SeasonNumber, int? EpisodeNumber);

/// <summary>Le domande delle segnalazioni alla libreria. Possono lanciare: chi chiama le protegge.</summary>
public interface IReportLibrary
{
    /// <summary>Il film, la serie, la stagione o l'episodio; null se non c'è, è un altro tipo o (stagione, episodio) non ha la serie.</summary>
    ReportedItem? Find(Guid itemId);
}
