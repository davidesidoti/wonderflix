import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
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

      expect(api.itemQueries.map((q) => q.searchTerm).toSet(), {'dune'});
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

      expect(api.itemQueries.map((q) => q.kinds), [
        {ItemKind.movie},
        {ItemKind.series},
      ]);
      expect(api.itemQueries.every((q) => q.includeProviderIds), isTrue);
    });
  });
}
