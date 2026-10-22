namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I filtri della pila del match (spec P §6.2), con gli stessi valori di
/// "Cosa guardo stasera?" nell'app: tipo movies/series/both, durata
/// any/90/120 (solo per i film), un genere per nome o nessuno, voto
/// any/good (7 o più)/bad (5 o meno) sul voto della community di Jellyfin.
/// </summary>
public sealed record MatchFilters(
    bool Movies, bool Series, TimeSpan? MaxRuntime, string? Genre, double? MinRating = null, double? MaxRating = null)
{
    /// <summary>Lunghezza massima del nome di un genere.</summary>
    public const int MaxGenreLength = 100;

    /// <summary>
    /// I filtri dei valori dell'app; null se uno non è valido. Tipo e durata
    /// e voto mancanti valgono "both" e "any" (l'app 0.16.0 non manda il
    /// voto); un genere vuoto vale "tutti".
    /// </summary>
    public static MatchFilters? Parse(string? type, string? duration, string? genre, string? rating = null)
    {
        var name = string.IsNullOrWhiteSpace(genre) ? null : genre.Trim();
        if (name is { Length: > MaxGenreLength }
            || duration is not (null or "any" or "90" or "120")
            || rating is not (null or "any" or "good" or "bad"))
        {
            return null;
        }

        double? min = rating == "good" ? 7 : null;
        double? max = rating == "bad" ? 5 : null;

        TimeSpan? limit = duration switch
        {
            "90" => TimeSpan.FromMinutes(90),
            "120" => TimeSpan.FromMinutes(120),
            _ => null,
        };
        return type switch
        {
            null or "both" => new MatchFilters(true, true, limit, name, min, max),
            "movies" => new MatchFilters(true, false, limit, name, min, max),
            "series" => new MatchFilters(false, true, limit, name, min, max),
            _ => null,
        };
    }
}
