using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Elementi ed eventi di riproduzione di Jellyfin come li vede l'attività degli amici (spec O).</summary>
public static class PlayingTitles
{
    /// <summary>Il film o l'episodio; null per ogni altro tipo (trailer, video, musica, serie…).</summary>
    public static PlayingTitle? From(BaseItem? item) => item switch
    {
        Movie movie => new PlayingTitle(movie.Id, movie.Name ?? string.Empty, movie.Id, null, null, null, null),
        Episode episode => new PlayingTitle(
            episode.Id,
            episode.Name ?? string.Empty,
            SeriesOf(episode),
            SeriesOf(episode),
            episode.SeriesName,
            episode.ParentIndexNumber,
            episode.IndexNumber),
        _ => null,
    };

    /// <summary>
    /// Il resoconto di un evento di riproduzione: solo dalle sessioni
    /// WonderFlix con un utente, per film ed episodi, e non gli avanzamenti
    /// che Jellyfin manda da sé ogni secondo (piano 21a, decisione 2).
    /// </summary>
    public static PlaybackReport? Report(PlaybackProgressEventArgs e)
    {
        var session = e.Session;
        if (e.IsAutomated
            || session is null
            || !string.Equals(session.Client, WatchPartyProtocol.ClientName, StringComparison.Ordinal)
            || session.UserId.Equals(Guid.Empty)
            || From(e.Item) is not { } title)
        {
            return null;
        }

        // LastPlaybackCheckIn è in UTC, a volte senza dirlo.
        return new PlaybackReport(
            session.Id,
            session.UserId,
            title.TitleId,
            e.PlaybackPositionTicks ?? 0,
            e is PlaybackStopEventArgs { PlayedToCompletion: true },
            new DateTimeOffset(DateTime.SpecifyKind(session.LastPlaybackCheckIn, DateTimeKind.Utc)));
    }

    private static Guid? SeriesOf(Episode episode) => episode.SeriesId == Guid.Empty ? null : episode.SeriesId;
}
