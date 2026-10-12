namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Le righe della Home di WonderFlix (spec M §6.1, spec N §6.7): id stabili,
/// nell'ordine predefinito. Il plugin li conosce solo per scartare quelli
/// sbagliati nella Home dell'admin; cosa mostrano lo decide l'app.
/// </summary>
public static class HomeRowIds
{
    public static readonly IReadOnlyList<string> Known =
    [
        "resume",
        "nextUp",
        "recommended",
        "requests",
        "latestMovies",
        "latestSeries",
        "becauseYouWatched",
        "continueSaga",
        "upcomingSeries",
        "upcomingMovies",
        "myList",
    ];

    /// <summary>
    /// Le righe nate dopo la 1.7.0 (spec N §6.7): una Home dell'admin salvata
    /// prima non le ha e, senza aggiungerle, sarebbero spente per tutti.
    /// </summary>
    public static readonly IReadOnlyList<string> AddedLater = ["recommended"];

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

    /// <summary>Le righe già viste dal testo salvato (`HomeRowsSeen`): id senza spazi, senza vuoti e doppioni.</summary>
    public static IReadOnlyList<string> ParseSeen(string? stored) =>
        stored is null
            ? []
            : stored.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Distinct(StringComparer.Ordinal)
                .ToList();

    /// <summary>
    /// La Home dell'admin con le righe di <see cref="AddedLater"/> non ancora
    /// viste (spec N §6.7): ognuna va subito dopo l'ultima riga accesa che la
    /// precede in <see cref="Known"/>, oppure in testa (la regola di spec M
    /// §6.4); una già accesa resta dov'è. Con rows null (mai impostata) le
    /// righe si segnano viste e basta (piano 20a, decisione 8). Null se non
    /// c'è niente da cambiare.
    /// </summary>
    public static (IReadOnlyList<string>? Rows, IReadOnlyList<string> Seen)? WithLaterRows(
        IReadOnlyList<string>? rows, IReadOnlyList<string> seen)
    {
        var missing = AddedLater.Where(id => !seen.Contains(id, StringComparer.Ordinal)).ToList();
        if (missing.Count == 0)
        {
            return null;
        }

        var result = rows?.ToList();
        if (result is not null)
        {
            foreach (var id in missing.Where(id => !result.Contains(id, StringComparer.Ordinal)))
            {
                var earlier = Known.TakeWhile(known => known != id).ToHashSet(StringComparer.Ordinal);
                result.Insert(result.FindLastIndex(earlier.Contains) + 1, id);
            }
        }

        return (result, seen.Concat(missing).ToList());
    }
}
