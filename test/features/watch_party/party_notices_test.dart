import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
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
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..itemsById['e5'] = testItem(
          id: 'e5',
          name: 'Cat\'s in the Bag',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 5,
          seasonIndex: 1)
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Dentro la zona finta: container, avvisi attivi, ingresso nel gruppo.
  void mount(FakeAsync async) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      libraryApiProvider.overrideWithValue(library),
    ]);
    container.listen(partyNoticesProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  void finish(FakeAsync async) {
    container.dispose();
    async.flushMicrotasks();
  }

  PartyNotice? current() => container.read(partyNoticesProvider);
  PartyNotices notices() => container.read(partyNoticesProvider.notifier);

  void emit(FakeAsync async, GroupUpdate update) {
    events.add(SyncPlayGroupUpdated(update));
    async.flushMicrotasks();
  }

  void seekCommand(FakeAsync async, Duration position) {
    events.add(SyncPlayCommandReceived(SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: 'p1',
      when: DateTime.utc(2100),
      position: position,
      type: SyncPlayCommandType.seek,
      emittedAt: DateTime.utc(2100),
    )));
    async.flushMicrotasks();
  }

  test('pausa e ripresa degli altri: uno alla volta, 3 s ciascuno', () {
    fakeAsync((async) {
      mount(async);
      expect(current(), isNull);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isFalse);
      async.elapse(PartyNotices.showFor);
      expect(current()?.kind, PartyNoticeKind.resumed);
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);
      finish(async);
    });
  });

  test('salto: con la posizione del comando; senza comando nessun avviso', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      expect(current(), isNull);

      seekCommand(async, const Duration(minutes: 32, seconds: 10));
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      expect(current()?.kind, PartyNoticeKind.seeked);
      expect(current()?.position, const Duration(minutes: 32, seconds: 10));
      finish(async);
    });
  });

  test('ripresa che fa partire il gruppo in attesa: senza aspettare', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
      expect(current(), isNull, reason: 'il buffering ha la sua schermata');
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.forcedResume);
      async.elapse(PartyNotices.showFor);

      // Ripresa durante l'attesa che non fa partire nessuno: ripresa normale.
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.resumed);
      finish(async);
    });
  });

  test('entrate e uscite', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const UserJoined('g1', 'Luigi'));
      expect(current()?.kind, PartyNoticeKind.joined);
      expect(current()?.name, 'Luigi');
      async.elapse(PartyNotices.showFor);
      emit(async, const UserLeft('g1', 'Luigi'));
      expect(current()?.kind, PartyNoticeKind.left);
      finish(async);
    });
  });

  test('le mie azioni: subito, e l\'eco del server entro 3 s non si ripete',
      () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused);
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isTrue);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);

      // Un'altra pausa, di qualcun altro: si mostra.
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current()?.mine, isFalse);
      finish(async);
    });
  });

  test('eco arrivata oltre 3 s: si mostra', () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused);
      async.elapse(const Duration(seconds: 4));
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current()?.kind, PartyNoticeKind.paused);
      expect(current()?.mine, isFalse);
      finish(async);
    });
  });

  test('la mia ripresa copre la ripresa senza aspettare', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
      notices().mine(PartyNoticeKind.resumed);
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      async.elapse(PartyNotices.showFor);
      expect(current(), isNull);
      finish(async);
    });
  });

  test('cambio di episodio e nuovo titolo', () {
    fakeAsync((async) {
      mount(async);
      // La prima coda dopo l'ingresso non è un cambio.
      emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
      expect(current(), isNull);

      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 1,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      expect(current()?.kind, PartyNoticeKind.nextEpisode);
      expect(current()?.title, 'S1:E5 · Cat\'s in the Bag');
      async.elapse(PartyNotices.showFor);

      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testQueue(
                  itemId: 'm2',
                  playlistItemId: 'p9',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
      expect(current()?.kind, PartyNoticeKind.nowWatching);
      expect(current()?.title, 'Arrival');
      finish(async);
    });
  });

  test('titolo non disponibile: nessun avviso', () {
    fakeAsync((async) {
      mount(async);
      emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 2,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      expect(current(), isNull, reason: 'e6 non è nella libreria finta');
      finish(async);
    });
  });

  test('avvisi diretti e uscita dal gruppo', () {
    fakeAsync((async) {
      mount(async);
      notices().show(const PartyNotice(PartyNoticeKind.resync));
      notices().show(const PartyNotice(PartyNoticeKind.paused));
      expect(current()?.kind, PartyNoticeKind.resync);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(current(), isNull);
      async.elapse(const Duration(seconds: 10));
      expect(current(), isNull, reason: 'la coda è stata svuotata');
      finish(async);
    });
  });
}
