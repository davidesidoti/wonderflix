import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel_state.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeLibraryApi library;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    library = FakeLibraryApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  void mount(FakeAsync async) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      libraryApiProvider.overrideWithValue(library),
    ]);
    container
      ..listen(queuePanelNavProvider, (_, _) {})
      ..listen(queueAddSearchProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  QueuePanelNav nav() => container.read(queuePanelNavProvider.notifier);
  QueueAddSearch search() => container.read(queueAddSearchProvider.notifier);

  test('viste: apri, indietro, azzera; fuori dal gruppo si azzera', () {
    fakeAsync((async) {
      mount(async);
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelQueue>());
      final series = testItem(id: 's1', name: 'Dark', kind: ItemKind.series);
      nav()
        ..open(const QueuePanelAdd())
        ..open(QueuePanelSeries(series));
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelSeries>());
      nav().back();
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelAdd>());
      nav()
        ..back()
        ..back();
      expect(container.read(queuePanelNavProvider), hasLength(1),
          reason: 'la vista Coda resta');
      nav().open(const QueuePanelAdd());
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(container.read(queuePanelNavProvider).last, isA<QueuePanelQueue>());
      container.dispose();
    });
  });

  test('viste: riaprire la vista in cima non la ripete', () {
    fakeAsync((async) {
      mount(async);
      final dark = testItem(id: 's1', name: 'Dark', kind: ItemKind.series);
      final other = testItem(id: 's2', name: 'Altra', kind: ItemKind.series);
      final season =
          testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.other);
      nav().open(const QueuePanelQueue());
      expect(container.read(queuePanelNavProvider), hasLength(1));
      nav()
        ..open(const QueuePanelAdd())
        ..open(const QueuePanelAdd())
        ..open(QueuePanelSeries(dark))
        ..open(QueuePanelSeries(dark));
      expect(container.read(queuePanelNavProvider), hasLength(3));
      nav().open(QueuePanelSeries(other));
      expect(container.read(queuePanelNavProvider), hasLength(4),
          reason: 'una serie diversa si apre');
      nav()
        ..open(QueuePanelSeason(other, season))
        ..open(QueuePanelSeason(other, season));
      expect(container.read(queuePanelNavProvider), hasLength(5));
      container.dispose();
    });
  });

  test('ricerca: da 2 lettere, dopo 300 ms, film e serie, al massimo 20', () {
    fakeAsync((async) {
      int? requestedLimit;
      library.onItems = (query, start, limit) {
        requestedLimit = limit;
        return pageOf([testItem(id: 'm1', name: 'Alien')]);
      };
      mount(async);
      search().setTerm('a');
      async.elapse(QueueAddSearch.debounce);
      expect(library.itemQueries, isEmpty, reason: 'una lettera sola');
      search().setTerm('al');
      async.elapse(const Duration(milliseconds: 200));
      search().setTerm('ali');
      async.elapse(QueueAddSearch.debounce);
      expect(library.itemQueries, hasLength(1));
      final query = library.itemQueries.single;
      expect(query.searchTerm, 'ali');
      expect(query.kinds, {ItemKind.movie, ItemKind.series});
      expect(requestedLimit, 20);
      expect(container.read(queueAddSearchProvider).results?.single.id, 'm1');
      expect(container.read(queueAddSearchProvider).term, 'ali');
      container.dispose();
    });
  });

  test('ricerca: errore, poi Riprova; azzera', () {
    fakeAsync((async) {
      library.error = const ServerUnreachableException();
      mount(async);
      search().setTerm('dark');
      async.elapse(QueueAddSearch.debounce);
      expect(container.read(queueAddSearchProvider).error, isNotNull);
      library.error = null;
      search().retry();
      async.flushMicrotasks();
      expect(container.read(queueAddSearchProvider).error, isNull);
      expect(container.read(queueAddSearchProvider).results, isNotNull);
      search().reset();
      expect(container.read(queueAddSearchProvider).term, '');
      expect(container.read(queueAddSearchProvider).results, isNull);
      container.dispose();
    });
  });

  test('ricerca: la risposta di un testo vecchio non compare', () {
    fakeAsync((async) {
      library
        ..delay = const Duration(seconds: 1)
        ..onItems = (query, start, limit) => pageOf(
            [testItem(id: query.searchTerm!, name: query.searchTerm!)]);
      mount(async);
      search().setTerm('al');
      async.elapse(QueueAddSearch.debounce);
      // La richiesta "al" è in volo: cambia il testo.
      search().setTerm('ali');
      async.elapse(const Duration(seconds: 1));
      expect(container.read(queueAddSearchProvider).results, isNull,
          reason: '"al" ha risposto, ma il testo ora è "ali"');
      async.elapse(const Duration(milliseconds: 400));
      expect(container.read(queueAddSearchProvider).results?.single.id, 'ali');
      container.dispose();
    });
  });

  test('ricerca: azzerare scarta la richiesta in volo', () {
    fakeAsync((async) {
      library
        ..delay = const Duration(seconds: 1)
        ..onItems = (query, start, limit) =>
            pageOf([testItem(id: 'm1', name: 'Alien')]);
      mount(async);
      search().setTerm('al');
      async.elapse(QueueAddSearch.debounce);
      search().reset();
      async.elapse(const Duration(seconds: 2));
      expect(container.read(queueAddSearchProvider).term, '');
      expect(container.read(queueAddSearchProvider).results, isNull);
      container.dispose();
    });
  });

  test('ricerca: uscendo dal gruppo si azzera', () {
    fakeAsync((async) {
      library.onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Alien')]);
      mount(async);
      search().setTerm('alien');
      async.elapse(QueueAddSearch.debounce);
      expect(container.read(queueAddSearchProvider).results, isNotNull);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(container.read(queueAddSearchProvider).term, '');
      expect(container.read(queueAddSearchProvider).results, isNull);
      container.dispose();
    });
  });

  test('episodi della serie: una richiesta sola', () {
    fakeAsync((async) {
      library.seriesEpisodes['s1'] = [testItem(id: 'e1')];
      mount(async);
      final sub = container.listen(
          queueSeriesEpisodesProvider('s1'), (_, _) {});
      async.flushMicrotasks();
      expect(container.read(queueSeriesEpisodesProvider('s1')).value?.single.id,
          'e1');
      expect(library.allEpisodesCalls, ['s1']);
      sub.close();
      container.dispose();
    });
  });
}
