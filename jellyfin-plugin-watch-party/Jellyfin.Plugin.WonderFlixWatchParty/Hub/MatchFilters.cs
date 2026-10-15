namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I filtri della pila del match (spec P §6.2), con gli stessi valori di
/// "Cosa guardo stasera?" nell'app: tipo movies/series/both, durata
/// any/90/120 (solo per i film), un genere per nome o nessuno.
/// </summary>
public sealed record MatchFilters(bool Movies, bool Series, TimeSpan? MaxRuntime, string? Genre)
{
    /// <summary>Lunghezza massima del nome di un genere.</summary>
    public const int MaxGenreLength = 100;

    /// <summary>
    /// I filtri dei valori dell'app; null se uno non è valido. Tipo e durata
    /// mancanti valgono "both" e "any"; un genere vuoto vale "tutti".
    /// </summary>
    public static MatchFilters? Parse(string? type, string? duration, string? genre)
    {
        var name = string.IsNullOrWhiteSpace(genre) ? null : genre.Trim();
        if (name is { Length: > MaxGenreLength } || duration is not (null or "any" or "90" or "120"))
        {
            return null;
        }

        TimeSpan? limit = duration switch
        {
            "90" => TimeSpan.FromMinutes(90),
            "120" => TimeSpan.FromMinutes(120),
            _ => null,
        };
        return type switch
        {
            null or "both" => new MatchFilters(true, true, limit, name),
            "movies" => new MatchFilters(true, false, limit, name),
            "series" => new MatchFilters(false, true, limit, name),
            _ => null,
        };
    }
}
