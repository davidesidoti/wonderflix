using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La domanda delle segnalazioni a Jellyfin (spec R §6.2): film, serie, stagione o episodio.</summary>
public sealed class JellyfinReportLibrary(ILibraryManager libraryManager) : IReportLibrary
{
    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public ReportedItem? Find(Guid itemId)
    {
        if (itemId == Guid.Empty)
        {
            return null;
        }

        switch (libraryManager.GetItemById(itemId))
        {
            case Movie movie:
                return new ReportedItem(movie.Id, "Movie", Name(movie.Name), movie.Id, Name(movie.Name), null, null);
            case Series series:
                return new ReportedItem(series.Id, "Series", Name(series.Name), series.Id, Name(series.Name), null, null);
            case Season { SeriesId: var seriesId } season when seriesId != Guid.Empty:
                return new ReportedItem(
                    season.Id, "Season", Name(season.Name), seriesId, Name(season.SeriesName), season.IndexNumber, null);
            case Episode { SeriesId: var seriesId } episode when seriesId != Guid.Empty:
                return new ReportedItem(
                    episode.Id, "Episode", Name(episode.Name), seriesId, Name(episode.SeriesName), episode.ParentIndexNumber, episode.IndexNumber);
            default:
                return null;
        }
    }

    private static string Name(string? name) => name ?? string.Empty;
}
