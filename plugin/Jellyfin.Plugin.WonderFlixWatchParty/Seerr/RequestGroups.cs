using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Gruppi della pagina Richieste e stati che ne dipendono (spec richieste-ui §4.2).</summary>
public static class RequestGroups
{
    public const string Open = "open";
    public const string Done = "done";
    public const string Closed = "closed";

    /// <summary>Una richiesta approvata da più di così, e ancora senza niente in arrivo, è "Non trovata".</summary>
    public static readonly TimeSpan NotFoundAfter = TimeSpan.FromDays(30);

    public static bool IsGroup(string? raw) => raw is Open or Done or Closed;

    /// <summary>Per decidere lo stato servono le date di Radarr: un film approvato da tempo, ancora da cercare.</summary>
    public static bool NeedsMovieDates(SeerrRequest request, DateTimeOffset now) =>
        IsMovie(request)
        && SeerrMapping.RequestStatus(request) == RequestStatuses.Approved
        && request.Media?.Status != SeerrCodes.MediaDeleted
        && now - request.CreatedAt > NotFoundAfter;

    /// <summary>Lo stato per l'app: quelli di <see cref="SeerrMapping.RequestStatus"/> più Tolta dal server e Non trovata.</summary>
    public static string StatusOf(SeerrRequest request, MovieDates? movie, DateTimeOffset now)
    {
        var status = SeerrMapping.RequestStatus(request);
        var mediaStatus = request.Media?.Status;

        if (mediaStatus == SeerrCodes.MediaDeleted
            && (request.Media?.DownloadStatus.Count ?? 0) == 0
            && status is RequestStatuses.Available or RequestStatuses.Approved or RequestStatuses.Partial)
        {
            return RequestStatuses.Removed;
        }

        if (status != RequestStatuses.Approved)
        {
            return status;
        }

        if (ReleaseRules.IsAwaitingRelease(movie, now))
        {
            return RequestStatuses.AwaitingRelease;
        }

        return now - request.CreatedAt > NotFoundAfter
            && mediaStatus is SeerrCodes.MediaUnknown or SeerrCodes.MediaPending or SeerrCodes.MediaProcessing
                ? RequestStatuses.NotFound
                : status;
    }

    public static string GroupOf(string status) => status switch
    {
        RequestStatuses.Available => Done,
        RequestStatuses.Declined or RequestStatuses.Failed or RequestStatuses.Removed or RequestStatuses.NotFound => Closed,
        _ => Open,
    };

    // Come RequestsService: senza tipo riconosciuto vale film.
    private static bool IsMovie(SeerrRequest request) => (request.Media?.MediaType ?? request.Type) != RequestMediaTypes.Tv;
}
