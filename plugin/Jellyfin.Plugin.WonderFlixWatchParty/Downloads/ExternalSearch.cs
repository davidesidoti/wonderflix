using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>Il link di ricerca su un tracker fuori da Prowlarr (MIRCrew), per quando la ricerca non trova niente.</summary>
public static partial class ExternalSearch
{
    public const string Placeholder = "{query}";

    /// <summary>Il modello con il titolo al posto di {query}; null se il modello è vuoto o senza {query}.</summary>
    public static string? UrlFor(string? template, string title) =>
        string.IsNullOrWhiteSpace(template) || !template.Contains(Placeholder, StringComparison.Ordinal)
            ? null
            : template.Replace(Placeholder, Uri.EscapeDataString(QueryOf(title)), StringComparison.Ordinal);

    // "Film (2008)" → "Film"; "Serie · S01E02" e "Serie · Stagione 3" → "Serie": i post usano il titolo di Sonarr/Radarr.
    internal static string QueryOf(string title)
    {
        var dot = title.IndexOf(" · ", StringComparison.Ordinal);
        var name = dot >= 0 ? title[..dot] : YearSuffix().Replace(title, "");
        return name.Trim();
    }

    [GeneratedRegex(@" \(\d{4}\)\s*$")]
    private static partial Regex YearSuffix();
}
