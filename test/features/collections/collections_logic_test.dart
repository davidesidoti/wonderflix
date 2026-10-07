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

  test('collectionKey: senza trattini e in minuscolo', () {
    expect(collectionKey('0088B3BF-1B19-EF2D-962F-A145C461538A'),
        '0088b3bf1b19ef2d962fa145c461538a');
  });

  test('indexCollections: dalla saga più piccola, a parità per nome, senza doppioni',
      () {
    final marvel = testCollection(id: 'c1', name: 'Marvel Universe', itemIds: ['m1', 'm2', 'm3']);
    final ironMan = testCollection(id: 'c2', name: 'Iron Man - Collezione', itemIds: ['M1', 'm2']);
    final avengers = testCollection(id: 'c3', name: 'Avengers - Collezione', itemIds: ['m1', 'm1', 'm4']);
    final index = indexCollections([marvel, ironMan, avengers]);
    expect(index['m1']!.map((c) => c.id), ['c3', 'c2', 'c1']);
    expect(index['m2']!.map((c) => c.id), ['c2', 'c1']);
    expect(index['m4']!.map((c) => c.id), ['c3']);
    expect(index['m9'], isNull);
  });

  test('filterCollections: il nome contiene il testo, senza maiuscole e accenti', () {
    final sagas = [
      testCollection(id: 'c1', name: 'Mátrix - Collezione'),
      testCollection(id: 'c2', name: 'Alien - Collezione'),
    ];
    expect(filterCollections(sagas, 'MATRIX').map((c) => c.id), ['c1']);
    expect(filterCollections(sagas, ' ').map((c) => c.id), ['c1', 'c2']);
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
