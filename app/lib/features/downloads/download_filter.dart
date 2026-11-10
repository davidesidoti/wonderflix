import '../../core/downloads/download_models.dart';

// Latin lowercase letters with a mark, folded to the plain letter: "Pokémon"
// is found by "pokemon".
const _folded = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ś': 's', 'š': 's', 'ß': 's',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
};

String _fold(String text) => [
      for (final c in text.toLowerCase().split('')) _folded[c] ?? c,
    ].join();

/// Il titolo contiene la ricerca, senza badare a maiuscole, accenti e spazi ai
/// lati della ricerca; una ricerca vuota corrisponde a tutto.
bool titleMatches(String title, String query) =>
    _fold(title).contains(_fold(query.trim()));

/// Una serie o un film con qualcosa da portare davanti con "Scarica subito".
class DownloadRushGroup {
  const DownloadRushGroup({
    required this.key,
    required this.title,
    required this.posterUrl,
    required this.missing,
    required this.canPress,
    required this.pending,
  });

  /// La riga da mandare a `rush`.
  final String key;
  final String title;
  final String? posterUrl;

  /// Le righe del gruppo intero con canRush o rush, anche quelle che il filtro
  /// non mostra; non conta quelle già in download o da ripassare.
  final int missing;

  /// C'è almeno una riga da portare davanti.
  final bool canPress;

  /// Le righe sono già state portate davanti e aspettano il loro turno.
  final bool pending;
}

/// I gruppi (una serie, un film) con almeno una riga che corrisponde a
/// [query] e almeno una che si può portare davanti o lo è già, nell'ordine
/// della prima riga di ognuno.
List<DownloadRushGroup> rushGroups(List<DownloadItem> waiting, String query) {
  // La serie è l'identità del gruppo; senza (film, plugin vecchio) la riga.
  final byId = <Object, List<DownloadItem>>{};
  for (final item in waiting) {
    (byId[item.seriesId ?? item.key] ??= []).add(item);
  }
  return [
    for (final rows in byId.values)
      if (rows.any((r) => titleMatches(r.title, query)) &&
          rows.any((r) => r.canRush || r.rush))
        _group(rows),
  ];
}

DownloadRushGroup _group(List<DownloadItem> rows) {
  final first = rows.first;
  final cut = first.title.lastIndexOf(' · ');
  final canPress = rows.any((r) => r.canRush && !r.rush);
  return DownloadRushGroup(
    // Senza riga con canRush (tutte già in coda) il tasto non si preme: la prima.
    key: (rows.where((r) => r.canRush && !r.rush).firstOrNull ??
            rows.where((r) => r.canRush).firstOrNull ??
            first)
        .key,
    title: first.kind == DownloadKind.movie || cut < 0
        ? first.title
        : first.title.substring(0, cut),
    posterUrl: rows.map((r) => r.posterUrl).nonNulls.firstOrNull,
    missing: rows.where((r) => r.canRush || r.rush).length,
    canPress: canPress,
    pending: !canPress && rows.any((r) => r.rush),
  );
}
