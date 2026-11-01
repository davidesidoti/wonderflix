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
