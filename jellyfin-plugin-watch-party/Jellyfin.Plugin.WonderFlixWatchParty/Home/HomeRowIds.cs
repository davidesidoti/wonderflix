namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Le righe della Home di WonderFlix (spec M §6.1): id stabili, nell'ordine
/// predefinito. Il plugin li conosce solo per scartare quelli sbagliati
/// nella Home dell'admin; cosa mostrano lo decide l'app.
/// </summary>
public static class HomeRowIds
{
    public static readonly IReadOnlyList<string> Known =
    [
        "resume",
        "nextUp",
        "requests",
        "latestMovies",
        "latestSeries",
        "becauseYouWatched",
        "continueSaga",
        "upcomingSeries",
        "upcomingMovies",
        "myList",
    ];

    /// <summary>Solo gli id conosciuti, scritti esatti (maiuscole comprese), senza doppioni, nell'ordine dato.</summary>
    public static IReadOnlyList<string> Normalize(IEnumerable<string?> rows) =>
        rows.OfType<string>()
            .Where(row => Known.Contains(row, StringComparer.Ordinal))
            .Distinct(StringComparer.Ordinal)
            .ToList();

    /// <summary>Come si salva nella configurazione: gli id separati da virgole.</summary>
    public static string Serialize(IReadOnlyList<string> rows) => string.Join(',', rows);

    /// <summary>Dal testo salvato: null se mai impostato, altrimenti l'elenco pulito (anche vuoto).</summary>
    public static IReadOnlyList<string>? Parse(string? stored) =>
        stored is null
            ? null
            : Normalize(stored.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
}
