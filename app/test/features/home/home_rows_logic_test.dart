import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_rows_logic.dart';

import '../../support/collections_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/requests_fakes.dart';

void main() {
  JellyfinItem episode(String id, String seriesId, String seriesName) =>
      testItem(
          id: id,
          name: 'Episodio',
          kind: ItemKind.episode,
          seriesId: seriesId,
          seriesName: seriesName);

  group('Perché hai visto X', () {
    test('becauseSources: gli episodi valgono come la serie, senza doppioni',
        () {
      final sources = becauseSources([
        episode('e1', 's1', 'Ms. Marvel'),
        episode('e2', 's1', 'Ms. Marvel'),
        episode('e3', 'S-1', 'Ms. Marvel'),
        testItem(id: 'm1', name: 'Dune'),
        testItem(id: 'x', name: 'Senza serie', kind: ItemKind.episode),
        episode('e4', 's2', 'The Bear'),
        testItem(id: 'm2', name: 'Arrival'),
      ]);
      expect(sources, [
        (id: 's1', name: 'Ms. Marvel'),
        (id: 'm1', name: 'Dune'),
        (id: 's2', name: 'The Bear'),
      ]);
    });

    test('becauseItems: film non visti e serie non finite, senza il titolo stesso',
        () {
      final items = becauseItems([
        testItem(id: 'S1', kind: ItemKind.series),
        testItem(id: 'a', name: 'Arrival'),
        testItem(id: 'b', name: 'Già visto', played: true),
        testItem(id: 'c', name: 'Serie finita', kind: ItemKind.series, played: true),
        testItem(id: 'd', name: 'Andor', kind: ItemKind.series),
        testItem(id: 'e', name: 'Episodio', kind: ItemKind.episode),
      ], 's1');
      expect(items.map((i) => i.id), ['a', 'd']);
      expect(
          becauseItems([for (var i = 0; i < 25; i++) testItem(id: 'm$i')], 'x'),
          hasLength(homeRowLimit));
    });

    test('loadBecauseYouWatched: se il primo titolo ha pochi simili, prova il dopo',
        () async {
      final api = FakeLibraryApi()
        ..playHistoryItems = [
          episode('e1', 's1', 'Ms. Marvel'),
          testItem(id: 'm1', name: 'Dune'),
        ]
        ..similarById['s1'] = [testItem(id: 'x1'), testItem(id: 'x2')]
        ..similarById['m1'] = [
          for (final id in ['a', 'b', 'c', 'd']) testItem(id: id),
        ];

      final content = await loadBecauseYouWatched(api, 'u1');

      expect(content!.sourceName, 'Dune');
      expect(content.items.map((i) => i.id), ['a', 'b', 'c', 'd']);
      expect(api.playHistoryCalls, [becauseHistoryLimit]);
      expect(api.similarCalls,
          [('s1', becauseSimilarLimit), ('m1', becauseSimilarLimit)]);
    });

    test('loadBecauseYouWatched: nessun titolo basta, niente riga', () async {
      final api = FakeLibraryApi()
        ..playHistoryItems = [testItem(id: 'm1', name: 'Dune')]
        ..similarItems = [testItem(id: 'a')];
      expect(await loadBecauseYouWatched(api, 'u1'), isNull);
      expect(await loadBecauseYouWatched(FakeLibraryApi(), 'u1'), isNull);
    });
  });

  test('Le mie richieste: in corso prima, poi le arrivate degli ultimi 30 giorni',
      () {
    final now = DateTime(2026, 10, 10, 12);
    MediaRequest request(int id, RequestStatus status, int daysAgo) =>
        testMediaRequest(
            id: id,
            status: status,
            createdAt: now.subtract(Duration(days: daysAgo)));
    final shown = homeRequests([
      request(1, RequestStatus.available, 2),
      request(2, RequestStatus.pending, 5),
      request(3, RequestStatus.declined, 1),
      request(4, RequestStatus.downloading, 1),
      request(5, RequestStatus.available, 31),
      request(6, RequestStatus.failed, 1),
      request(7, RequestStatus.approved, 3),
      request(8, RequestStatus.partial, 9),
      request(9, RequestStatus.available, 30),
    ], now);
    expect(shown.map((r) => r.id), [4, 7, 2, 8, 1, 9]);
    expect(
        homeRequests([
          for (var i = 0; i < 30; i++) request(i, RequestStatus.pending, i),
        ], now),
        hasLength(homeRowLimit));
  });

  group('Continua la saga', () {
    test('sagasToContinue: iniziate e non finite, dalla visione più recente',
        () {
      final candidates = sagasToContinue([
        testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2', 'm3']),
        testCollection(id: 'c2', name: 'Alien', itemIds: ['a1', 'a2']),
        testCollection(id: 'c3', name: 'Finita', itemIds: ['f1']),
        testCollection(id: 'c4', name: 'Mai vista', itemIds: ['n1', 'n2']),
      ], ['A2', 'f1', 'm1', 'm2', 'a2']);
      expect([for (final c in candidates) c.saga.id], ['c2', 'c1']);
      expect(candidates.first.unwatched, ['a1']);
      expect(candidates.first.watched, 1);
      expect(candidates.last.unwatched, ['m3']);
      expect(candidates.last.watched, 2);
      expect(
          sagasToContinue([
            for (var i = 0; i < 15; i++)
              testCollection(id: 'c$i', name: 'S$i', itemIds: ['p$i', 'u$i']),
          ], [for (var i = 0; i < 15; i++) 'p$i']),
          hasLength(homeSagaLimit));
    });

    test('nextInSaga: il primo non visto in ordine di uscita', () {
      final next = nextInSaga([
        testItem(id: 'm3', name: 'Revolutions', premiereDate: '2003-11-05T00:00:00Z'),
        testItem(id: 'm2', name: 'Reloaded', premiereDate: '2003-05-15T00:00:00Z'),
        testItem(id: 'm9', name: 'Senza data', year: 2021),
        testItem(id: 'm0', name: 'Visto', premiereDate: '1990-01-01T00:00:00Z', played: true),
      ]);
      expect(next!.id, 'm2');
      expect(nextInSaga([testItem(id: 'x', played: true)]), isNull);
      expect(nextInSaga(const []), isNull);
    });

    test('loadContinueSaga: una chiamata per i titoli, saghe senza titoli saltate',
        () async {
      final api = FakeLibraryApi()
        ..playedMovieItems = [testItem(id: 'm1'), testItem(id: 'a1')]
        ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
      final sagas = await loadContinueSaga(api, 'u1', [
        testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
        testCollection(id: 'c2', name: 'Alien', itemIds: ['a1', 'a2']),
      ]);
      expect(api.playedMoviesCalls, [playedMoviesLimit]);
      expect(api.itemsByIdsCalls.single, unorderedEquals(['m2', 'a2']));
      expect(sagas.single.saga.id, 'c1');
      expect(sagas.single.next.name, 'Matrix Reloaded');
      expect(sagas.single.watched, 1);
      expect(sagas.single.total, 2);

      final none = FakeLibraryApi();
      expect(await loadContinueSaga(none, 'u1', const []), isEmpty);
      expect(none.playedMoviesCalls, isEmpty);
    });
  });

  test('contenuti vuoti', () {
    expect(const ItemsRowContent([]).isEmpty, isTrue);
    expect(const RequestsRowContent([]).isEmpty, isTrue);
    expect(const SagasRowContent([]).isEmpty, isTrue);
    expect(const UpcomingSeriesRowContent([]).isEmpty, isTrue);
    expect(const UpcomingMoviesRowContent([]).isEmpty, isTrue);
    expect(BecauseYouWatchedContent(sourceName: 'x', items: [testItem()]).isEmpty,
        isFalse);
  });

  test('AwaitingReleaseIsAnOpenRequest', () {
    final now = DateTime(2026, 10, 10, 12);
    final shown = homeRequests([
      testMediaRequest(
          id: 1,
          status: RequestStatus.awaitingRelease,
          createdAt: now.subtract(const Duration(days: 60))),
    ], now);
    expect(shown.map((r) => r.id), [1]);
  });
}
