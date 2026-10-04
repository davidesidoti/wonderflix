import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/party_queue_editor.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late FakePartyNotices notices;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi();
    notices = FakePartyNotices();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  void emit(FakeAsync async, PlayQueue queue) {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    async.flushMicrotasks();
  }

  /// Nel gruppo, con la coda e3 (p1, già visto), e4 (p2, in riproduzione),
  /// e5 (p3), e6 (p4). Con [queueFeature] il plugin è il 1.3.0.
  void mount(FakeAsync async, {bool queueFeature = true}) {
    channelApi.install(
        version: '1.3.0',
        features: queueFeature ? const {partyQueueFeature} : const {});
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyChannelApiProvider.overrideWithValue(channelApi),
      partyNoticesProvider.overrideWith(() => notices),
    ]);
    container.listen(partyChannelProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
    emit(
        async,
        testSeriesQueue(
            itemIds: const ['e3', 'e4', 'e5', 'e6'], playingIndex: 1));
    api.calls.clear();
  }

  void finish(FakeAsync async) {
    container.dispose();
    async.flushMicrotasks();
  }

  PartyQueueEditor editor() => container.read(partyQueueEditorProvider);

  List<Object?> announced() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingAction) event.action.wire,
      ];

  test('salto: solo verso un altro elemento della coda, annunciato', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().jumpTo('p4'));
      unawaited(editor().jumpTo('p2'));
      unawaited(editor().jumpTo('p9'));
      async.flushMicrotasks();
      expect(api.calls, ['set-item p4']);
      expect(announced(), ['SetCurrentItem']);
      finish(async);
    });
  });

  test('rimozione: mai l\'elemento in riproduzione, senza annuncio', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().remove('p3'));
      unawaited(editor().remove('p1'));
      unawaited(editor().remove('p2'));
      unawaited(editor().remove('p9'));
      async.flushMicrotasks();
      expect(api.calls, ['remove p3', 'remove p1']);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('spostamento: solo tra i prossimi, con l\'indice del server', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().move('p4', 0));
      unawaited(editor().move('p3', 0));
      unawaited(editor().move('p1', 0));
      unawaited(editor().move('p4', 2));
      async.flushMicrotasks();
      expect(api.calls, ['move p4 2'],
          reason: 'p3 è già lì, p1 è già visto, 2 è fuori dai prossimi');
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('ordine casuale: solo se cambia; la propria eco non fa avvisi', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, isEmpty, reason: '"ordinato" su una coda ordinata: 500');

      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle on']);
      expect(notices.hiddenMineCalls, [PartyNoticeKind.shuffleOn]);
      expect(announced(), ['ShuffleMode']);

      emit(
          async,
          testSeriesQueue(
              itemIds: const ['e4', 'e6', 'e3', 'e5'],
              shuffled: true,
              reason: 'ShuffleMode',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5)));
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls.last, 'shuffle off');
      expect(notices.hiddenMineCalls.last, PartyNoticeKind.shuffleOff);
      finish(async);
    });
  });

  test('plugin senza la funzione queue: comandi sì, annunci no', () {
    fakeAsync((async) {
      mount(async, queueFeature: false);
      unawaited(editor().jumpTo('p3'));
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, ['set-item p3', 'shuffle on']);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('richiesta fallita: avviso "Non riuscito", niente annuncio', () {
    fakeAsync((async) {
      mount(async);
      api.error = const ServerUnreachableException();
      unawaited(editor().jumpTo('p3'));
      async.flushMicrotasks();
      expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('rimozione e spostamento falliti: avviso "Non riuscito"', () {
    fakeAsync((async) {
      mount(async);
      api.error = const ServerUnreachableException();
      unawaited(editor().remove('p3'));
      async.flushMicrotasks();
      expect(notices.shown.map((n) => n.kind), [PartyNoticeKind.queueFailed]);
      unawaited(editor().move('p4', 0));
      async.flushMicrotasks();
      expect(notices.shown.map((n) => n.kind),
          [PartyNoticeKind.queueFailed, PartyNoticeKind.queueFailed]);
      finish(async);
    });
  });

  test('ordine casuale fallito: l\'eco registrata si toglie', () {
    fakeAsync((async) {
      mount(async);
      api.error = const ServerUnreachableException();
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(notices.hiddenMineCalls, [PartyNoticeKind.shuffleOn]);
      expect(notices.forgotten, [PartyNoticeKind.shuffleOn]);
      expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);
      expect(announced(), isEmpty);
      finish(async);
    });
  });

  test('ordine casuale riuscito: l\'eco resta', () {
    fakeAsync((async) {
      mount(async);
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(notices.forgotten, isEmpty);
      finish(async);
    });
  });

  test('richiesta fallita dopo l\'uscita dal gruppo: nessun avviso', () {
    fakeAsync((async) {
      mount(async);
      api.error = const ServerUnreachableException();
      unawaited(editor().jumpTo('p3'));
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      expect(api.calls, contains('set-item p3'));
      expect(notices.shown, isEmpty);
      finish(async);
    });
  });

  test('fuori dal gruppo: niente', () {
    fakeAsync((async) {
      mount(async);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      api.calls.clear();
      unawaited(editor().jumpTo('p3'));
      unawaited(editor().remove('p3'));
      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      finish(async);
    });
  });
}
