namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Le azioni che la panoramica offre per una voce (spec "Serve te" §5.6); la prima è la consigliata.</summary>
public static class DownloadActions
{
    public const string GrabBest = "GrabBest";

    public const string Pick = "Pick";

    public const string SearchNow = "SearchNow";

    public const string Snooze = "Snooze";

    public const string Import = "Import";

    public const string Discard = "Discard";

    /// <summary>Apre la ricerca sul tracker esterno; sempre l'ultima, con il link nella voce.</summary>
    public const string ExternalSearch = "ExternalSearch";

    /// <summary>Le azioni di For, più ExternalSearch se la ricerca non ha trovato niente di buono e c'è un link.</summary>
    public static IReadOnlyList<string> For(DownloadEntry entry, string? externalSearchUrl) =>
        externalSearchUrl is not null && OffersExternalSearch(entry) ? [.. For(entry), ExternalSearch] : For(entry);

    internal static bool OffersExternalSearch(DownloadEntry entry) =>
        entry is { State: DownloadStates.NeedsYou, Reason: DownloadReasons.NothingFound or DownloadReasons.BelowMinScore };

    public static IReadOnlyList<string> For(DownloadEntry entry)
    {
        if (entry.State != DownloadStates.NeedsYou)
        {
            // Fermo sui metadati: si può scartare a mano senza aspettare le ore della soglia.
            return entry.State == DownloadStates.Downloading && entry.MetadataSince is not null ? [Pick, SearchNow, Discard] : [Pick, SearchNow];
        }

        var canGrab = entry.Kind != DownloadKinds.Season;
        switch (entry.Reason)
        {
            case DownloadReasons.BelowMinScore:
                return canGrab ? [GrabBest, Pick, SearchNow] : [Pick, SearchNow];
            case DownloadReasons.NothingFound:
                return entry.Summary switch
                {
                    { StopgapAvailable: true } when canGrab => [GrabBest, Pick, SearchNow, Snooze],
                    { Found: 0 } => [Snooze, SearchNow],
                    _ => [Pick, SearchNow, Snooze],
                };
            case DownloadReasons.ImportBlocked:
                return entry.DownloadId is null ? [Discard] : [Import, Discard];
            default:
                return [Pick, SearchNow];
        }
    }
}
