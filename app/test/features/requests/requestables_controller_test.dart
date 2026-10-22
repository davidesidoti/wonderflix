import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requestables_controller.dart';
import 'package:wonderflix/features/search/search_controller.dart';

import '../../support/library_fakes.dart';
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
    final library =
        LibraryMatches(itemIds: {'EE39BEF06F503DD0E9DBD20593DF417F'.toLowerCase()});
    expect(visibleRequestables(titles, library).map((t) => t.tmdbId), [2, 3]);
  });

  test('senza id Jellyfin da Seerr, il titolo si riconosce da id TMDB e tipo',
      () {
    // Seerr non ha ancora l'id Jellyfin dei titoli aggiunti dopo la
    // scansione della notte: fa fede l'id TMDB dei risultati della libreria.
    final titles = [
      testRequestable(tmdbId: 1),
      testRequestable(tmdbId: 1, type: RequestMediaType.tv),
      testRequestable(tmdbId: 2),
      testRequestable(tmdbId: 3, type: RequestMediaType.tv),
      testRequestable(tmdbId: 3),
    ];
    const library = LibraryMatches(movieTmdbIds: {1}, seriesTmdbIds: {3});
    expect(
        visibleRequestables(titles, library)
            .map((t) => (t.mediaType, t.tmdbId)),
        [
          (RequestMediaType.tv, 1),
          (RequestMediaType.movie, 2),
          (RequestMediaType.movie, 3),
        ]);
  });

  test('LibraryMatches dai risultati: id in minuscolo, TMDB per tipo', () {
    final library = LibraryMatches.fromResults(SearchResults(
      movies: [
        testItem(id: 'EE39', tmdbId: 438631),
        testItem(id: 'AAA'),
      ],
      series: [
        testItem(id: 'S1', kind: ItemKind.series, tmdbId: 90228),
      ],
      people: [testItem(id: 'p1', kind: ItemKind.person, tmdbId: 5)],
    ));
    expect(library.itemIds, {'ee39', 'aaa', 's1'});
    expect(library.movieTmdbIds, {438631});
    expect(library.seriesTmdbIds, {90228});
  });
}
