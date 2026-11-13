using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// Quello che serve a scartare una release di Prowlarr come farebbe Sonarr/Radarr. <c>Blocklist</c> contiene già solo le
/// voci del titolo cercato (chi costruisce il contesto filtra per <c>SeriesId</c>/<c>MovieId</c>); <c>MinSeeders</c> è per id indexer
/// del servizio; <c>TitleTags</c> sono i tag della serie/film.
/// </summary>
public sealed record ChecksContext(
    ArrQualityProfile? Profile,
    IReadOnlyList<ArrQualityDefinition> Definitions,
    IReadOnlyList<ArrReleaseProfile> ReleaseProfiles,
    IReadOnlyList<ArrBlocklistItem> Blocklist,
    IReadOnlyDictionary<int, int> MinSeeders,
    IReadOnlyList<int> TitleTags);

/// <summary>I motivi di scarto che Sonarr/Radarr non danno alle release di Prowlarr (spec ricerche-prowlarr §5).</summary>
public static class ReleaseChecks
{
    private const double BytesPerMegabyte = 1024 * 1024;

    /// <summary>
    /// Il motivo per scartare la release (<c>Blocklisted</c>, <c>Restricted</c>, <c>NotWanted</c>) e un dettaglio breve, o null se
    /// passa. <paramref name="seasonMinutes"/>: la durata di tutta la stagione, per il peso di un pack completo.
    /// Con <paramref name="skipQuality"/> salta solo il controllo "qualità non ammessa" (serve a riconoscere il tappabuchi 720p).
    /// </summary>
    public static (string Reason, string? Detail)? Check(ArrRelease r, ChecksContext c, int runtimeMinutes, int? seasonMinutes = null, bool skipQuality = false)
    {
        if (c.Blocklist.Any(b => string.Equals(b.SourceTitle, r.Title, StringComparison.OrdinalIgnoreCase)))
        {
            return ("Blocklisted", null);
        }

        // shortcut: i termini sono testo semplice, non le espressioni /regex/ che Sonarr ammette; da cambiare se un profilo le usa.
        var title = r.Title ?? string.Empty;
        foreach (var profile in c.ReleaseProfiles.Where(p => p.Enabled && (p.Tags is not { Count: > 0 } || p.Tags.Intersect(c.TitleTags).Any())))
        {
            // Come Sonarr: basta uno dei termini obbligatori.
            if (profile.Required is { Count: > 0 } required && !required.Any(t => Contains(title, t)))
            {
                return ("Restricted", string.Join(", ", required));
            }

            var banned = profile.Ignored?.FirstOrDefault(t => Contains(title, t));
            if (banned is not null)
            {
                return ("Restricted", banned);
            }
        }

        var quality = r.Quality?.Quality;
        if (!skipQuality && c.Profile is { } qualityProfile && quality is not null && !DownloadRule.IsAllowed(qualityProfile, quality.Id))
        {
            return ("NotWanted", quality.Name);
        }

        // Un pack completo, come per Sonarr, si misura su tutta la stagione (seasonMinutes); senza saperla niente massimo, e il
        // minimo sugli episodi della regola.
        var (minMinutes, maxMinutes) = !r.FullSeason ? (runtimeMinutes, runtimeMinutes)
            : seasonMinutes is > 0 and var season ? (season, season)
            : (runtimeMinutes, 0);
        var definition = quality is null ? null : c.Definitions.FirstOrDefault(d => d.Quality?.Id == quality.Id);
        if (definition is not null && r.Size > 0)
        {
            // MinSize/MaxSize sono MB al minuto; 0 o null = nessun limite (anche con durata sconosciuta, 0).
            var min = (definition.MinSize ?? 0) * minMinutes * BytesPerMegabyte;
            var max = (definition.MaxSize ?? 0) * maxMinutes * BytesPerMegabyte;
            if ((min > 0 && r.Size < min) || (max > 0 && r.Size > max))
            {
                return ("NotWanted", "Size");
            }
        }

        if (r.Seeders is { } seeders && c.MinSeeders.TryGetValue(r.IndexerId, out var minSeeders) && seeders < minSeeders)
        {
            return ("NotWanted", "Seeders");
        }

        if (c.Profile is { } scored && r.CustomFormatScore < scored.MinFormatScore)
        {
            return ("NotWanted", "Score");
        }

        return null;
    }

    private static bool Contains(string title, string term) => title.Contains(term, StringComparison.OrdinalIgnoreCase);
}
