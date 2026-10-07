import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/collections/collections_logic.dart';

import '../../support/collections_fakes.dart';
import '../../support/library_fakes.dart';

void main() {
  test('foldForSearch: minuscolo, senza accenti e senza spazi ai lati', () {
    expect(foldForSearch('  Mátrix ÉÈ '), 'matrix ee');
    expect(foldForSearch('Amélie, Pinocchio, Ñandú'), 'amelie, pinocchio, nandu');
  });

  test('foldForSearch: accenti scritti come lettera più segno, macron e lettere speciali',
      () {
    // 'e' più accento acuto combinante.
    expect(foldForSearch('Amélie'), 'amelie');
    // 'İ' in minuscolo diventa 'i' più un puntino combinante.
    expect(foldForSearch('İstanbul'), 'istanbul');
    expect(foldForSearch('Shōgun'), 'shogun');
    expect(foldForSearch('Ā Ē Ī Ō Ū'), 'a e i o u');
    expect(foldForSearch('Ørsted'), 'orsted');
    expect(foldForSearch('Æon Flux, Cœur, Straße'), 'aeon flux, coeur, strasse');
    expect(foldForSearch('Šaša Čapek Žižek Łukasz'), 'sasa capek zizek lukasz');
  });

  test('indexCollections: dalla saga più piccola, a parità per nome, senza doppioni',
      () {
    final marvel = testCollection(id: 'c1', name: 'Marvel Universe', itemIds: ['m1', 'm2', 'm3']);
    final ironMan = testCollection(id: 'c2', name: 'Iron Man - Collezione', itemIds: ['m1', 'm2']);
    final avengers = testCollection(id: 'c3', name: 'Avengers - Collezione', itemIds: ['m1', 'm4']);
    // La stessa saga due volte nell'elenco non si ripete nell'indice.
    final index = indexCollections([marvel, ironMan, avengers, marvel]);
    expect(index['m1']!.map((c) => c.id), ['c3', 'c2', 'c1']);
    expect(index['m2']!.map((c) => c.id), ['c2', 'c1']);
    expect(index['m4']!.map((c) => c.id), ['c3']);
    expect(index['m9'], isNull);
  });

  test('filterCollections: il nome contiene il testo, senza maiuscole e accenti', () {
    final sagas = [
      testCollection(id: 'c1', name: 'Mátrix - Collezione'),
      testCollection(id: 'c2', name: 'Alien - Collezione'),
      testCollection(id: 'c3', name: 'Matrix - Collezione'),
    ];
    expect(filterCollections(sagas, 'MATRIX').map((c) => c.id), ['c1', 'c3']);
    // L'accento nel testo cercato non conta: "mátrix" trova anche "Matrix".
    expect(filterCollections(sagas, 'mátrix').map((c) => c.id), ['c1', 'c3']);
    expect(filterCollections(sagas, ' ').map((c) => c.id), ['c1', 'c2', 'c3']);
    expect(filterCollections(sagas, 'zzz'), isEmpty);
  });

  test('matchCollections: in ordine di nome, al massimo [max], niente con un testo vuoto',
      () {
    final sagas = [
      for (final name in ['Star Wars', 'Star Trek', 'Stargate', 'Alien'])
        testCollection(id: name, name: name),
    ];
    expect(matchCollections(sagas, 'star', max: 2).map((c) => c.name),
        ['Star Trek', 'Star Wars']);
    expect(matchCollections(sagas, '  ', max: 12), isEmpty);
  });

  test('sortCollections: per nome, per numero di film, per data di aggiunta', () {
    final alien = testCollection(
        id: 'a', name: 'Alien', itemIds: ['1', '2'], dateCreated: DateTime.utc(2026, 1, 1));
    final matrix = testCollection(
        id: 'm', name: 'Matrix', itemIds: ['1', '2', '3'], dateCreated: DateTime.utc(2026, 6, 1));
    final dune = testCollection(id: 'd', name: 'Dune', itemIds: ['1', '2']);
    final sagas = [matrix, dune, alien];
    expect(sortCollections(sagas, CollectionSort.name).map((c) => c.id), ['a', 'd', 'm']);
    expect(sortCollections(sagas, CollectionSort.size).map((c) => c.id), ['m', 'a', 'd']);
    // Senza data in fondo.
    expect(sortCollections(sagas, CollectionSort.dateAdded).map((c) => c.id), ['m', 'a', 'd']);
    // L'elenco di partenza non cambia.
    expect(sagas.map((c) => c.id), ['m', 'd', 'a']);
  });

  test('sortCollections: a parità l\'ordine è fisso (nome, poi id)', () {
    // Senza data tutte e due: per nome.
    final noDates = [
      testCollection(id: 'z', name: 'Zeta'),
      testCollection(id: 'b', name: 'Beta'),
      testCollection(id: 'a', name: 'Alfa'),
    ];
    expect(sortCollections(noDates, CollectionSort.dateAdded).map((c) => c.id),
        ['a', 'b', 'z']);
    // Con la stessa data: per nome.
    final sameDate = DateTime.utc(2026, 3, 1);
    final dated = [
      testCollection(id: 'b', name: 'Beta', dateCreated: sameDate),
      testCollection(id: 'a', name: 'Alfa', dateCreated: sameDate),
    ];
    expect(sortCollections(dated, CollectionSort.dateAdded).map((c) => c.id),
        ['a', 'b']);
    // Con lo stesso nome: per id, in qualunque ordine partano.
    final twins = [
      testCollection(id: 'x2', name: 'Gemelle'),
      testCollection(id: 'x1', name: 'Gemelle'),
    ];
    for (final sort in CollectionSort.values) {
      expect(sortCollections(twins, sort).map((c) => c.id), ['x1', 'x2']);
      expect(sortCollections(twins.reversed.toList(), sort).map((c) => c.id),
          ['x1', 'x2']);
    }
  });

  test('sagaTarget e watchedCount', () {
    UserItemData data(JellyfinItem item) => item.userData;
    final first = testItem(id: 'm1', played: true);
    final second = testItem(id: 'm2', positionTicks: 10);
    final third = testItem(id: 'm3');
    expect(sagaTarget([first, second, third], data)!.id, 'm2');
    expect(sagaTarget([first, testItem(id: 'm4', played: true)], data)!.id, 'm1');
    expect(sagaTarget(const [], data), isNull);
    expect(watchedCount([first, second, third], data), 1);
  });
}
