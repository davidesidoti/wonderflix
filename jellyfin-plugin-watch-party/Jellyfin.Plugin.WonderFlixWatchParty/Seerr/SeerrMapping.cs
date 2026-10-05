using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Regole pure da Seerr agli oggetti per l'app (spec I §7.3).</summary>
public static class SeerrMapping
{
    /// <summary>L'anno da una data di Seerr ("2024-02-27"); null se manca.</summary>
    public static int? Year(string? date) =>
        date is { Length: >= 4 }
        && int.TryParse(date.AsSpan(0, 4), NumberStyles.None, CultureInfo.InvariantCulture, out var year)
            ? year
            : null;

    /// <summary>Un id Jellyfin in qualunque formato; null se non è un Guid valido o è vuoto.</summary>
    public static Guid? ParseGuid(string? raw) =>
        Guid.TryParse(raw, out var id) && id != Guid.Empty ? id : null;

    /// <summary>L'id Jellyfin per l'app: formato "N" minuscolo, o null.</summary>
    public static string? JellyfinId(string? raw) => ParseGuid(raw)?.ToString("N");

    /// <summary>Stato di un titolo o di una stagione; sconosciuto, bloccato ed eliminato valgono None.</summary>
    public static string TitleStatus(int? mediaStatus) => mediaStatus switch
    {
        SeerrCodes.MediaPending => TitleStatuses.Pending,
        SeerrCodes.MediaProcessing => TitleStatuses.Processing,
        SeerrCodes.MediaPartial => TitleStatuses.Partial,
        SeerrCodes.MediaAvailable => TitleStatuses.Available,
        _ => TitleStatuses.None,
    };

    public static bool IsBlocklisted(SeerrMediaInfo? info) => info?.Status == SeerrCodes.MediaBlocklisted;

    /// <summary>Richiesta ancora aperta: in attesa o approvata.</summary>
    public static bool IsActive(SeerrRequest request) =>
        request.Status is SeerrCodes.RequestPending or SeerrCodes.RequestApproved;

    /// <summary>C'è una richiesta aperta per il titolo.</summary>
    public static bool Requested(SeerrMediaInfo? info) => info is not null && info.Requests.Any(IsActive);

    /// <summary>C'è una richiesta aperta dell'utente Seerr seerrUserId.</summary>
    public static bool RequestedBy(SeerrMediaInfo? info, int? seerrUserId) =>
        seerrUserId is { } me && info is not null && info.Requests.Any(r => IsActive(r) && r.RequestedBy?.Id == me);

    /// <summary>Le stagioni della serie senza gli speciali (0), in ordine, con lo stato di ognuna.</summary>
    public static IReadOnlyList<SeasonDto> Seasons(SeerrTv tv) =>
        tv.Seasons
            .Where(s => s.SeasonNumber > 0)
            .OrderBy(s => s.SeasonNumber)
            .Select(s => new SeasonDto(s.SeasonNumber, s.EpisodeCount, SeasonStatus(tv.MediaInfo, s.SeasonNumber)))
            .ToList();

    /// <summary>
    /// Lo stato della stagione in Seerr; senza uno stato suo, In attesa o In
    /// lavorazione se una richiesta aperta la contiene (spec I §7.3).
    /// </summary>
    public static string SeasonStatus(SeerrMediaInfo? info, int seasonNumber)
    {
        var own = TitleStatus(info?.Seasons.FirstOrDefault(s => s.SeasonNumber == seasonNumber)?.Status);
        if (own != TitleStatuses.None || info is null)
        {
            return own;
        }

        var requests = info.Requests.Where(r => r.Seasons.Any(s => s.SeasonNumber == seasonNumber)).ToList();
        if (requests.Any(r => r.Status == SeerrCodes.RequestPending))
        {
            return TitleStatuses.Pending;
        }

        return requests.Any(r => r.Status == SeerrCodes.RequestApproved) ? TitleStatuses.Processing : TitleStatuses.None;
    }

    /// <summary>
    /// Stato di una richiesta per l'app. Rifiutata, non riuscita, in attesa e
    /// completata seguono il codice della richiesta. Se è approvata: titolo
    /// disponibile, download in corso, almeno una stagione chiesta già arrivata
    /// (in parte), altrimenti approvata. Lo stato dell'intera serie non decide
    /// nulla: una serie in parte disponibile non dice se è arrivato ciò che è
    /// stato chiesto (spec I §7.3 e decisione 1 del piano 15a).
    /// </summary>
    public static string RequestStatus(SeerrRequest request) => request.Status switch
    {
        SeerrCodes.RequestDeclined => RequestStatuses.Declined,
        SeerrCodes.RequestFailed => RequestStatuses.Failed,
        SeerrCodes.RequestPending => RequestStatuses.Pending,
        SeerrCodes.RequestCompleted => RequestStatuses.Available,
        _ when request.Media?.Status == SeerrCodes.MediaAvailable => RequestStatuses.Available,
        _ when request.Media?.DownloadStatus.Count > 0 => RequestStatuses.Downloading,
        _ when request.Seasons.Any(s => s.Status == SeerrCodes.RequestCompleted) => RequestStatuses.Partial,
        _ => RequestStatuses.Approved,
    };

    /// <summary>Avanzamento del primo download, da 0 a 1; null senza dimensione.</summary>
    public static double? Progress(IReadOnlyList<SeerrDownload> downloads) =>
        downloads.Count > 0 && downloads[0].Size > 0
            ? Math.Clamp(1 - (downloads[0].SizeLeft / downloads[0].Size), 0, 1)
            : null;

    /// <summary>Il trailer su YouTube: prima "Trailer", poi "Teaser"; solo indirizzi http o https.</summary>
    public static string? TrailerUrl(IEnumerable<SeerrVideo> videos)
    {
        var youtube = videos.Where(v => v.Site == "YouTube" && IsWebUrl(v.Url)).ToList();
        return (youtube.FirstOrDefault(v => v.Type == "Trailer") ?? youtube.FirstOrDefault(v => v.Type == "Teaser"))?.Url;
    }

    /// <summary>I nomi dei generi, senza quelli vuoti.</summary>
    public static IReadOnlyList<string> Genres(IEnumerable<SeerrGenre> genres) =>
        genres.Select(g => g.Name).OfType<string>().Where(n => n.Length > 0).ToList();

    private static bool IsWebUrl(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp);
}
