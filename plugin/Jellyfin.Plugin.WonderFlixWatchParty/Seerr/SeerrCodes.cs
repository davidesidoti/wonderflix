namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Codici di stato di Seerr (spec I §3).</summary>
public static class SeerrCodes
{
    // Stato di una richiesta (MediaRequestStatus).
    public const int RequestPending = 1;
    public const int RequestApproved = 2;
    public const int RequestDeclined = 3;
    public const int RequestFailed = 4;
    public const int RequestCompleted = 5;

    // Stato di un titolo o di una stagione (MediaStatus).
    public const int MediaUnknown = 1;
    public const int MediaPending = 2;
    public const int MediaProcessing = 3;
    public const int MediaPartial = 4;
    public const int MediaAvailable = 5;
    public const int MediaBlocklisted = 6;
    public const int MediaDeleted = 7;
}

/// <summary>I servizi di Seerr per le approvazioni.</summary>
public static class SeerrServices
{
    public const string Radarr = "radarr";
    public const string Sonarr = "sonarr";
}
