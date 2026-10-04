import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/party_queue_items.dart';
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
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(id: 'e4', name: 'Pilot')
      ..itemsById['e5'] = testItem(id: 'e5', name: 'Cat');
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
    container.listen(partyQueueItemsProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  void emit(FakeAsync async, PlayQueue queue) {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    async.flushMicrotasks();
  }

  Map<String, Object?> items() => container.read(partyQueueItemsProvider);

  test('i titoli in coda si chiedono insieme; i mancanti valgono null', () {
    fakeAsync((async) {
      mount(async);
      emit(async, testSeriesQueue());
      expect(library.itemsByIdsCalls, [
        ['e4', 'e5', 'e6'],
      ]);
      expect(items().keys, ['e4', 'e5', 'e6']);
      expect(items()['e6'], isNull, reason: 'e6 non è nella libreria');

      // Solo gli id nuovi.
      emit(
          async,
          testSeriesQueue(
              itemIds: const ['e4', 'e5', 'e6', 'e7'],
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      expect(library.itemsByIdsCalls.last, ['e7']);
      container.dispose();
    });
  });

  test('richiesta fallita: si riprova al prossimo aggiornamento', () {
    fakeAsync((async) {
      mount(async);
      library.error = const ServerUnreachableException();
      emit(async, testSeriesQueue());
      expect(items(), isEmpty);
      library.error = null;
      emit(async,
          testSeriesQueue(lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      expect(library.itemsByIdsCalls.last, ['e4', 'e5', 'e6']);
      expect(items().keys, ['e4', 'e5', 'e6']);
      container.dispose();
    });
  });

  test('uscita dal gruppo: la mappa si svuota', () {
    fakeAsync((async) {
      mount(async);
      emit(async, testSeriesQueue());
      expect(items(), isNotEmpty);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(items(), isEmpty);
      container.dispose();
    });
  });
}
