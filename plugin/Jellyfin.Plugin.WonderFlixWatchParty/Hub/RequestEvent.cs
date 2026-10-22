namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un evento del webhook di Seerr già letto (spec I §7.5): Title è il
/// subject di Seerr, ItemId l'id Jellyfin in formato "N" se Seerr lo conosce.
/// </summary>
public sealed record RequestEvent(
    int RequestId, string MediaType, int TmdbId, string Title, IReadOnlyList<int>? Seasons, string? ItemId);
