import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.collectionsTab, 'Saghe');
    expect(it.collectionsCount(1), '1 saga');
    expect(it.collectionsCount(101), '101 saghe');
    expect(it.collectionFilmCount(1), '1 film');
    expect(it.collectionFilmCount(3), '3 film');
    expect(it.collectionWatched(1), '1 visto');
    expect(it.collectionWatched(0), '0 visti');
    expect(it.collectionPartOf('Matrix - Collezione'), 'Fa parte di: Matrix - Collezione');
    expect(it.collectionPlay('Matrix'), 'Riproduci "Matrix"');
    expect(it.collectionResume('Matrix'), 'Riprendi "Matrix"');
    expect(en.collectionsTab, 'Collections');
    expect(en.collectionsCount(2), '2 collections');
    expect(en.collectionFilmCount(1), '1 movie');
    expect(en.collectionPartOf('Alien'), 'Part of: Alien');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.collectionThisMovie,
        l.collectionsSearchHint,
        l.collectionsSortName,
        l.collectionsSortSize,
        l.collectionsEmpty,
        l.collectionsNoMatch,
      ], everyElement(isNotEmpty));
    }
  });
}
