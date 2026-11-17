import '../../core/jellyfin/item_models.dart';
import '../collections/collections_logic.dart';

/// Articoli iniziali che il punteggio salta, già piegati (spec §8.2).
const searchArticles = [
  "l'", 'il ', 'lo ', 'la ', 'i ', 'gli ', 'le ', "un'", 'un ', 'uno ', //
  'una ', 'the ', 'a ', 'an ',
];

/// Sezioni dei risultati di Cerca, nell'ordine a parità di punteggio.
enum SearchSection { sagas, movies, series, people }

/// [foldForSearch] con l'apostrofo tipografico (U+2019) come `'`.
String _fold(String text) => foldForSearch(text).replaceAll('’', "'");

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Posizione in [folded] dell'occorrenza di [term] che dà il punteggio
/// migliore, col punteggio (0 inizio o dopo l'articolo, 1 inizio di parola,
/// 2 dentro); `null` se non c'è.
(int, int)? _bestHit(String folded, String term) {
  if (term.isEmpty) return null;
  if (folded.startsWith(term)) return (0, 0);
  for (final article in searchArticles) {
    if (folded.startsWith(article) &&
        folded.startsWith(term, article.length)) {
      return (article.length, 0);
    }
  }
  final first = folded.indexOf(term);
  if (first < 0) return null;
  for (var i = first; i >= 0; i = folded.indexOf(term, i + 1)) {
    if (i == 0 || !_wordChar.hasMatch(folded[i - 1])) return (i, 1);
  }
  return (first, 2);
}

/// Quanto [name] corrisponde a [term]: 0 comincia col termine (anche dopo un
/// articolo), 1 una parola comincia col termine, 2 lo contiene, 3 lo contiene
/// solo [originalTitle]; `null` se nessuno dei due.
int? matchScore(String term, String name, {String? originalTitle}) {
  final folded = _fold(term);
  final hit = _bestHit(_fold(name), folded);
  if (hit != null) return hit.$2;
  if (folded.isEmpty || originalTitle == null) return null;
  return _fold(originalTitle).contains(folded) ? 3 : null;
}

/// Il miglior risultato per [term] (spec §8.2): un film o una serie con
/// punteggio 0 o 1 sul nome, o una persona il cui nome comincia col termine
/// se nessun titolo ha 0; `null` se nessuno.
JellyfinItem? bestResult(String term,
    {required List<JellyfinItem> movies,
    required List<JellyfinItem> series,
    required List<JellyfinItem> people}) {
  final folded = _fold(term);
  if (folded.isEmpty) return null;
  JellyfinItem? best;
  int? bestRank;
  for (final item in [...movies, ...series]) {
    final score = matchScore(term, item.name);
    if (score == null || score > 1) continue;
    // Punteggio, poi i già iniziati, poi le serie; a parità il primo arrivato.
    final rank = score * 4 +
        (item.userData.progress != null ? 0 : 2) +
        (item.kind == ItemKind.series ? 0 : 1);
    if (bestRank == null || rank < bestRank) (best, bestRank) = (item, rank);
  }
  if (best != null && bestRank! < 4) return best;
  for (final person in people) {
    if (_fold(person.name).startsWith(folded)) return person;
  }
  return best;
}

/// Inizio e fine (esclusa) in [name] del pezzo da sottolineare per [term]:
/// l'occorrenza che dà il punteggio, sennò la prima; `null` se non c'è.
(int, int)? highlightRange(String name, String term) {
  // Il nome piegato lettera per lettera, con dove comincia e finisce in
  // [name] ogni carattere piegato ('æ' → due, un accento combinante → zero).
  final folded = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var offset = 0;
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    final plain = char.trim().isEmpty ? char : _fold(char);
    for (var k = 0; k < plain.length; k++) {
      starts.add(offset);
      ends.add(offset + char.length);
    }
    folded.write(plain);
    offset += char.length;
  }
  final foldedTerm = _fold(term);
  final hit = _bestHit(folded.toString(), foldedTerm);
  if (hit == null) return null;
  final start = starts[hit.$1];
  var end = ends[hit.$1 + foldedTerm.length - 1];
  // Gli accenti combinanti dopo l'ultima lettera restano con la lettera.
  while (end < name.length &&
      name.codeUnitAt(end) >= 0x0300 &&
      name.codeUnitAt(end) <= 0x036F) {
    end++;
  }
  return (start, end);
}

/// [items] con i soli punteggio 3 (solo il titolo originale) in fondo; per
/// il resto l'ordine resta.
List<JellyfinItem> originalLast(String term, List<JellyfinItem> items) {
  bool onlyOriginal(JellyfinItem item) =>
      matchScore(term, item.name, originalTitle: item.originalTitle) == 3;
  return [
    for (final item in items)
      if (!onlyOriginal(item)) item,
    for (final item in items)
      if (onlyOriginal(item)) item,
  ];
}

/// Le sezioni di [firstNames] per punteggio del loro primo elemento (senza
/// corrispondenza in fondo), a parità nell'ordine di [SearchSection].
List<SearchSection> sectionOrder(
    String term, Map<SearchSection, String> firstNames,
    {Map<SearchSection, String?> firstOriginals = const {}}) {
  int rank(SearchSection section) =>
      (matchScore(term, firstNames[section]!,
                  originalTitle: firstOriginals[section]) ??
              4) *
          SearchSection.values.length +
      section.index;
  return [
    for (final section in SearchSection.values)
      if (firstNames.containsKey(section)) section,
  ]..sort((a, b) => rank(a) - rank(b));
}
