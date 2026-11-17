import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/search/search_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
    container.listen(searchControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'Dune: Prophecy', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]))
      ..people = [testItem(id: 'p1', name: 'Denis Villeneuve', kind: ItemKind.person)];
  });

  test('meno di 2 lettere: nessuna ricerca', () {
    fakeAsync((async) {
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('d');
      async.elapse(const Duration(seconds: 1));
      expect(api.itemQueries, isEmpty);
      expect(container.read(searchControllerProvider).results, isNull);
    });
  });

  test('attende 300 ms dall\'ultima lettera e cerca una volta', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(searchControllerProvider.notifier);
      controller.setTerm('du');
      async.elapse(const Duration(milliseconds: 200));
      controller.setTerm('dune');
      async.elapse(const Duration(milliseconds: 299));
      expect(api.itemQueries, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      async.flushMicrotasks();

      expect(api.itemQueries.map((q) => q.searchTerm).toSet(), {'dune', null});
      expect(api.itemQueries.where((q) => q.searchTerm == null),
          everyElement(predicate<ItemQuery>((q) => q.personId == 'p1')));
      final results = container.read(searchControllerProvider).results!;
      expect(results.movies.single.name, 'Dune');
      expect(results.series.single.name, 'Dune: Prophecy');
      expect(results.people.single.name, 'Denis Villeneuve');
      expect(results.isEmpty, isFalse);
    });
  });

  test('chiede anche i ProviderIds di film e serie, per "Da richiedere"', () {
    fakeAsync((async) {
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('dune');
      async.elapse(SearchController.debounce + const Duration(milliseconds: 1));
      async.flushMicrotasks();

      final searches = api.itemQueries.where((q) => q.searchTerm != null);
      expect(searches.map((q) => q.kinds), [
        {ItemKind.movie},
        {ItemKind.series},
      ]);
      expect(searches.every((q) => q.includeProviderIds), isTrue);
    });
  });

  test('i totali arrivano dalla risposta', () {
    fakeAsync((async) {
      api
        ..onItems = ((query, start, limit) => query.personId != null
            ? pageOf([])
            : query.kinds.contains(ItemKind.series)
                ? pageOf([], 0)
                : pageOf([testItem(id: 'm1', name: 'Dune')], 15))
        ..peopleTotal = 459;
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('dune');
      async.elapse(const Duration(milliseconds: 350));
      async.flushMicrotasks();

      final results = container.read(searchControllerProvider).results!;
      expect(results.movieTotal, 15);
      expect(results.seriesTotal, 0);
      expect(results.peopleTotal, 459);
    });
  });

  test('le prime sei persone: titolo noto, numero di titoli, riordinate', () {
    fakeAsync((async) {
      final a = testItem(id: 'a', name: 'A');
      final b = testItem(id: 'b', name: 'B', people: [
        {'Id': 'p2', 'Name': 'P2', 'Type': 'Director'},
      ]);
      api
        ..people = [
          for (var i = 1; i <= 7; i++)
            testItem(id: 'p$i', name: 'P$i', kind: ItemKind.person),
        ]
        ..onItems = ((query, start, limit) => switch (query.personId) {
              null => pageOf([]),
              'p1' => pageOf([a], 2),
              'p2' => pageOf([b], 10),
              _ => pageOf([], 0),
            });
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('ist');
      async.elapse(const Duration(milliseconds: 350));
      async.flushMicrotasks();

      final r = container.read(searchControllerProvider).results!;
      final personQueries = api.itemQueries.where((q) => q.personId != null);
      expect(personQueries.map((q) => q.personId),
          ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
      expect(
          personQueries.every((q) =>
              q.includePeople &&
              q.sort == CatalogSort.rating &&
              q.kinds.containsAll({ItemKind.movie, ItemKind.series})),
          isTrue);
      expect(r.people.map((p) => p.id).take(2), ['p2', 'p1']);
      expect(r.people.map((p) => p.id).skip(2), ['p3', 'p4', 'p5', 'p6', 'p7']);
      expect(r.facts!['p2']!.titles, 10);
      expect(r.facts!['p2']!.knownFor.id, 'b');
      expect(r.facts!['p2']!.roleType, 'Director');
      expect(r.facts!['p1']!.roleType, isNull);
      expect(r.facts!.containsKey('p3'), isFalse);
    });
  });

  test('i risultati arrivano prima dei dati delle persone', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      api.itemsGateFor = (query) => query.personId != null ? gate : null;
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('dune');
      async.elapse(const Duration(milliseconds: 350));
      async.flushMicrotasks();

      final state = container.read(searchControllerProvider);
      expect(state.loading, isFalse);
      expect(state.results!.movies.single.name, 'Dune');
      expect(state.results!.facts, isNull);
      gate.complete();
      async.flushMicrotasks();
      expect(container.read(searchControllerProvider).results!.facts!.keys, ['p1']);
    });
  });

  test('un termine nuovo scarta i dati delle persone del vecchio', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      api
        ..itemsGateFor = ((query) =>
            query.personId != null && query.searchTerm == null ? gate : null)
        ..onItems = ((query, start, limit) => query.personId != null
            ? pageOf([testItem(id: 'x')], 3)
            : pageOf([testItem(id: 'm1', name: query.searchTerm!)]));
      final container = makeContainer();
      final controller = container.read(searchControllerProvider.notifier);
      controller.setTerm('dune');
      async.elapse(const Duration(milliseconds: 350));
      async.flushMicrotasks();
      controller.setTerm('alien');
      gate.complete();
      async.flushMicrotasks();

      final state = container.read(searchControllerProvider);
      expect(state.term, 'alien');
      expect(state.loading, isTrue);
      expect(state.results!.facts, isNull);
    });
  });

  test('submit cerca subito, senza aspettare i 300 ms', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(searchControllerProvider.notifier);
      controller.setTerm('dune');
      controller.submit();
      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();
      expect(api.itemQueries.map((q) => q.searchTerm).toSet(), {'dune', null});
      expect(container.read(searchControllerProvider).results!.movies, isNotEmpty);

      // Il timer annullato non cerca una seconda volta.
      final count = api.itemQueries.length;
      async.elapse(const Duration(seconds: 1));
      expect(api.itemQueries.length, count);
    });
  });

  test('submit senza attesa né termine: niente', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(searchControllerProvider.notifier);
      controller.setTerm('d');
      controller.submit();
      async.elapse(const Duration(seconds: 1));
      expect(api.itemQueries, isEmpty);
    });
  });

  test('la ricerca chiede titolo originale, trama e conteggio degli episodi', () {
    fakeAsync((async) {
      final container = makeContainer();
      container.read(searchControllerProvider.notifier).setTerm('dune');
      async.elapse(const Duration(milliseconds: 350));
      async.flushMicrotasks();

      final searches = api.itemQueries.where((q) => q.searchTerm != null);
      expect(searches, hasLength(2));
      expect(searches.every((q) => q.includeSearchFields && q.includeOverview),
          isTrue);
      expect(api.peopleCalls.single.$3, 12);
    });
  });
}
