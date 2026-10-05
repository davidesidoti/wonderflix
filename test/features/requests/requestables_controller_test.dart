import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requestables_controller.dart';
import 'package:wonderflix/features/search/search_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  ProviderContainer makeContainer({bool available = true}) {
    final container = ProviderContainer.test(
      overrides: requestsTestOverrides(api, available: available),
      retry: (_, _) => null,
    );
    container.listen(requestablesControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(tmdbId: 1, title: 'Dune'),
        testRequestable(
            tmdbId: 2, title: 'Dune: Prophecy', type: RequestMediaType.tv),
      ];
  });

  test('attende come la ricerca e cerca una volta, nella lingua data', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('du', language: 'it');
      async.elapse(const Duration(milliseconds: 100));
      controller.setTerm(' dune ', language: 'it');
      expect(container.read(requestablesControllerProvider).loading, isTrue);

      async.elapse(SearchController.debounce);
      async.flushMicrotasks();

      expect(api.calls, ['search:dune']);
      expect(api.searchLanguages, ['it']);
      final state = container.read(requestablesControllerProvider);
      expect(state.term, 'dune');
      expect(state.loading, isFalse);
      expect(state.titles!.map((t) => t.title), ['Dune', 'Dune: Prophecy']);
    });
  });

  test('meno di 2 lettere o funzione spenta: nessuna ricerca', () {
    fakeAsync((async) {
      final short = makeContainer();
      short.read(requestablesControllerProvider.notifier).setTerm('d', language: 'it');
      final off = makeContainer(available: false);
      off.read(requestablesControllerProvider.notifier).setTerm('dune', language: 'it');
      async.elapse(const Duration(seconds: 1));

      expect(api.calls, isEmpty);
      expect(short.read(requestablesControllerProvider).loading, isFalse);
      expect(off.read(requestablesControllerProvider).titles, isNull);
    });
  });

  test('la risposta di un termine superato si scarta', () {
    fakeAsync((async) {
      final gate = api.searchGate = Completer<void>();
      api.searchResults['dunes'] = [testRequestable(tmdbId: 3, title: 'Dunes')];
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('dune', language: 'it');
      async.elapse(SearchController.debounce);
      controller.setTerm('dunes', language: 'it');
      async.elapse(SearchController.debounce);
      gate.complete();
      async.flushMicrotasks();

      final state = container.read(requestablesControllerProvider);
      expect(state.term, 'dunes');
      expect(state.titles!.single.title, 'Dunes');
    });
  });

  test('errore, poi Riprova', () {
    fakeAsync((async) {
      api.failure = RequestsFailure.seerrUnavailable;
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('dune', language: 'it');
      async.elapse(SearchController.debounce);
      async.flushMicrotasks();
      expect(container.read(requestablesControllerProvider).error,
          isA<RequestsException>());

      api.failure = null;
      controller.retry(language: 'it');
      expect(container.read(requestablesControllerProvider).loading, isTrue);
      async.flushMicrotasks();

      final state = container.read(requestablesControllerProvider);
      expect(state.error, isNull);
      expect(state.titles, hasLength(2));
    });
  });

  test('i titoli già trovati nella libreria non si ripetono', () {
    final titles = [
      testRequestable(
          tmdbId: 1,
          status: TitleStatus.available,
          jellyfinItemId: 'ee39bef06f503dd0e9dbd20593df417f'),
      testRequestable(tmdbId: 2, status: TitleStatus.available, jellyfinItemId: 'aaa'),
      testRequestable(tmdbId: 3),
    ];
    expect(
        visibleRequestables(titles, {'EE39BEF06F503DD0E9DBD20593DF417F'.toLowerCase()})
            .map((t) => t.tmdbId),
        [2, 3]);
  });
}
