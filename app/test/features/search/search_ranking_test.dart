import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/search/search_ranking.dart';

import '../../support/library_fakes.dart';

void main() {
  group('matchScore', () {
    final cases = <(String, String, String?, int?)>[
      ('ist', "L'Istituto", null, 0),
      ('ist', 'L’Istituto', null, 0),
      ("l'ist", 'L’Istituto', null, 0),
      ('l’ist', "L'Istituto", null, 0),
      ('IST', "L'Istituto", null, 0),
      ('cas', 'La casa di carta', null, 0),
      ('pad', 'Il padrino', null, 0),
      ('wre', 'The Wrestler', null, 0),
      ('quiet', 'A Quiet Place', null, 0),
      ('altra', "Un'altra vita", null, 0),
      ('the', 'The Wrestler', null, 0),
      ('gli inc', 'Gli Incredibili', null, 0),
      ('dune', 'Dune: Parte Due', null, 0),
      ('citta', 'Citt\u00e0 di Dio', null, 0),
      ('citt\u00e0', 'Citta\u0300 di Dio', null, 0),
      ('citta\u0300', 'Citt\u00e0 di Dio', null, 0),
      ('fist', "Marvel's Iron Fist", null, 1),
      ('iron fist', "Marvel's Iron Fist", null, 1),
      ('list', 'The Terminal List: Lupo Nero', null, 1),
      ('ist', 'Il mistero di Istanbul', null, 1),
      ('ist', 'Il mistero della pietra', null, 2),
      ('tra', 'Lo straniero', null, 2),
      (
        'ist',
        'Maleficent - Signora del male',
        'Maleficent: Mistress of Evil',
        3,
      ),
      ('ist', "L'Istituto", 'The Institute', 0),
      ('ist', 'Dune', null, null),
      ('dune parte due e altro', 'Dune', null, null),
      ('', 'Dune', null, null),
      ('  ', 'Dune', null, null),
    ];
    // Nel nome del test un accento combinante non si distingue: lo si dice.
    String shown(String text) => text.contains('\u0300') ? '$text (NFD)' : text;
    for (final (term, name, original, score) in cases) {
      test(
        '"${shown(term)}" in "${shown(name)}" vale $score',
        () => expect(matchScore(term, name, originalTitle: original), score),
      );
    }
  });

  group('bestResult', () {
    JellyfinItem m(String n, {double? progress}) =>
        testItem(id: n, name: n, playedPercentage: progress);
    JellyfinItem s(String n) => testItem(id: n, name: n, kind: ItemKind.series);
    JellyfinItem p(String n) => testItem(id: n, name: n, kind: ItemKind.person);
    // (caso, termine, film, serie, persone, nome atteso o null)
    final cases =
        <
          (
            String,
            String,
            List<JellyfinItem>,
            List<JellyfinItem>,
            List<JellyfinItem>,
            String?,
          )
        >[
          (
            'per "ist" L\'Istituto',
            'ist',
            [m('Il mistero della pietra')],
            [s("Marvel's Iron Fist"), s("L'Istituto")],
            [p('Christian Bale')],
            "L'Istituto",
          ),
          (
            'solo "contiene": nessuna carta',
            'ist',
            [m('Il mistero della pietra')],
            [],
            [],
            null,
          ),
          (
            'il più basso',
            'dun',
            [m('Le grandi dune'), m('Dune')],
            [],
            [],
            'Dune',
          ),
          (
            'a parità la serie',
            'dune',
            [m('Dune')],
            [s('Dune: Prophecy')],
            [],
            'Dune: Prophecy',
          ),
          (
            'a parità il già iniziato',
            'dune',
            [m('Dune', progress: 40)],
            [s('Dune: Prophecy')],
            [],
            'Dune',
          ),
          (
            'a parità tra serie la prima',
            'dark',
            [],
            [s('Dark'), s('Dark Matter')],
            [],
            'Dark',
          ),
          (
            'persona che comincia batte un 1',
            'christ',
            [m('Il ritorno di Christine')],
            [],
            [p('Christopher Nolan')],
            'Christopher Nolan',
          ),
          (
            'un titolo con 0 batte la persona',
            'christ',
            [m('Christine')],
            [],
            [p('Christopher Nolan')],
            'Christine',
          ),
          (
            'persona che lo contiene soltanto',
            'ist',
            [],
            [],
            [p('Christian Bale')],
            null,
          ),
          (
            'tra più persone la prima',
            'chris',
            [],
            [],
            [p('Chris Pratt'), p('Christopher Nolan')],
            'Chris Pratt',
          ),
          (
            'un 3 non vince mai',
            'mistress',
            [
              testItem(
                id: 'mal',
                name: 'Maleficent - Signora del male',
                originalTitle: 'Mistress of Evil',
              ),
            ],
            [],
            [],
            null,
          ),
          ('termine vuoto', '', [m('Dune')], [], [p('Dune Man')], null),
        ];
    for (final (name, term, movies, series, people, expected) in cases) {
      test(
        name,
        () => expect(
          bestResult(
            term,
            movies: movies,
            series: series,
            people: people,
          )?.name,
          expected,
        ),
      );
    }
  });

  group('highlightRange', () {
    test(
      "dopo l'articolo",
      () => expect(highlightRange("L'Istituto", 'ist'), (2, 5)),
    );
    test(
      'apostrofo tipografico',
      () => expect(highlightRange('L’Istituto', "l'ist"), (0, 5)),
    );
    test(
      'lettera accentata (NFC)',
      () => expect(highlightRange('Citt\u00e0 di Dio', 'citta'), (0, 5)),
    );
    test(
      'lettera più accento combinante (NFD): comprende il segno',
      () => expect(highlightRange('Citta\u0300 di Dio', 'citta'), (0, 6)),
    );
    test(
      'NFD in mezzo: il segno conta nella posizione',
      () => expect(highlightRange('Citta\u0300 di Dio', 'a di'), (4, 9)),
    );
    test(
      'ß si piega in due lettere',
      () => expect(highlightRange('Straße', 'strass'), (0, 5)),
    );
    test(
      'emoji prima del nome (due unità UTF-16)',
      () => expect(highlightRange('😀Dune', 'dune'), (2, 6)),
    );
    test('maiuscole', () => expect(highlightRange('Dune', 'DUN'), (0, 3)));
    test(
      'più parole',
      () => expect(highlightRange("Marvel's Iron Fist", 'iron fist'), (9, 18)),
    );
    test(
      "l'inizio di parola prima del pezzo interno",
      () => expect(highlightRange('Il mistero di Istanbul', 'ist'), (14, 17)),
    );
    test(
      'dentro una parola',
      () => expect(highlightRange('Lo straniero', 'tra'), (4, 7)),
    );
    test(
      'lettera che si piega in due',
      () => expect(highlightRange('Ægir', 'aeg'), (0, 2)),
    );
    test(
      'nessuna corrispondenza',
      () => expect(highlightRange('Dune', 'ist'), isNull),
    );
    test('termine vuoto', () => expect(highlightRange('Dune', ' '), isNull));
    test(
      'termine più lungo del nome',
      () => expect(highlightRange('Dune', 'dune parte due'), isNull),
    );
  });

  test("originalLast porta in fondo solo i titoli originali, nell'ordine", () {
    // a: 2, b: 3, c: 0, d: 3 → a, c, b, d
    final items = [
      testItem(id: 'a', name: 'Il mistero della pietra'),
      testItem(id: 'b', name: 'Maleficent', originalTitle: 'Mistress of Evil'),
      testItem(id: 'c', name: "L'Istituto"),
      testItem(id: 'd', name: 'Il re', originalTitle: 'The Kingdom of Istria'),
    ];
    expect(originalLast('ist', items).map((i) => i.id), ['a', 'c', 'b', 'd']);
  });

  test(
    "sectionOrder: per punteggio del primo elemento, a parità l'ordine fisso",
    () {
      expect(
        sectionOrder('ist', {
          SearchSection.movies: 'Il mistero della pietra',
          SearchSection.series: "L'Istituto",
          SearchSection.people: 'Christian Bale',
        }),
        [SearchSection.series, SearchSection.movies, SearchSection.people],
      );
      expect(
        sectionOrder('dune', {
          SearchSection.series: 'Dune: Prophecy',
          SearchSection.movies: 'Dune',
        }),
        [SearchSection.movies, SearchSection.series],
      );
    },
  );

  test(
    'sectionOrder: il titolo originale conta, senza corrispondenza in fondo',
    () {
      expect(
        sectionOrder(
          'mistress',
          {
            SearchSection.sagas: 'Dune',
            SearchSection.movies: 'Maleficent',
            SearchSection.people: 'Mistress Jane',
          },
          firstOriginals: {SearchSection.movies: 'Mistress of Evil'},
        ),
        [SearchSection.people, SearchSection.movies, SearchSection.sagas],
      );
    },
  );
}
