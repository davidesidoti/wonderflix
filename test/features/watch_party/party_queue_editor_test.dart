import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/party_queue_editor.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
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
  /// e5 (p3), e6 (p4). Con [queueFeature] il plugin è il 1.3.0. Con
  /// [library] gli avvisi sono quelli veri (con i dettagli dei titoli da
  /// lì), e quelli mostrati finiscono in [shown].
  void mount(FakeAsync async,
      {bool queueFeature = true,
      FakeLibraryApi? library,
      List<PartyNotice>? shown}) {
    channelApi.install(
        version: '1.3.0',
        features: queueFeature ? const {partyQueueFeature} : const {});
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyChannelApiProvider.overrideWithValue(channelApi),
      if (library == null)
        partyNoticesProvider.overrideWith(() => notices)
      else
        libraryApiProvider.overrideWithValue(library),
    ]);
    container.listen(partyChannelProvider, (_, _) {});
    if (library != null) {
      container.listen(partyNoticesProvider, (_, notice) {
        if (notice != null) shown?.add(notice);
      });
    }
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

  /// La coda del server dopo un cambio di ordine; [minute] ne cambia
  /// `lastUpdate`.
  void emitShuffled(FakeAsync async, {required bool shuffled, int minute = 5}) =>
      emit(
          async,
          testSeriesQueue(
              itemIds: const ['e3', 'e4', 'e5', 'e6'],
              playingIndex: 1,
              shuffled: shuffled,
              reason: 'ShuffleMode',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, minute)));

  test('ordine casuale: due clic di fila, una sola richiesta', () {
    fakeAsync((async) {
      mount(async);
      emitShuffled(async, shuffled: true);
      unawaited(editor().setShuffle(false));
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off'],
          reason: 'la coda cambia solo con la risposta del server: un secondo '
              '"ordinato" su una coda già ordinata fa rispondere 500');
      expect(announced(), ['ShuffleMode']);
      expect(notices.hiddenMineCalls, [PartyNoticeKind.shuffleOff]);
      finish(async);
    });
  });

  test('ordine casuale: senza la coda nuova del server si riprova dopo '
      'shuffleSettleTimeout', () {
    fakeAsync((async) {
      mount(async);
      emitShuffled(async, shuffled: true);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      async.elapse(
          PartyQueueEditor.shuffleSettleTimeout - const Duration(milliseconds: 1));
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off'], reason: 'il tempo non è finito');

      async.elapse(const Duration(milliseconds: 1));
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off', 'shuffle off']);
      expect(announced(), ['ShuffleMode', 'ShuffleMode']);
      finish(async);
    });
  });

  test('ordine casuale: richiesta fallita, si può riprovare subito', () {
    fakeAsync((async) {
      mount(async);
      emitShuffled(async, shuffled: true);
      api.error = const ServerUnreachableException();
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);

      api.error = null;
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off', 'shuffle off']);
      expect(announced(), ['ShuffleMode'], reason: 'solo la richiesta riuscita');
      finish(async);
    });
  });

  test('ordine casuale: con la coda nuova del server il blocco finisce', () {
    fakeAsync((async) {
      mount(async);
      emitShuffled(async, shuffled: true);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      emitShuffled(async, shuffled: false, minute: 6);

      unawaited(editor().setShuffle(true));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off', 'shuffle on']);
      expect(announced(), ['ShuffleMode', 'ShuffleMode']);
      finish(async);
    });
  });

  test('ordine casuale: il server che risponde piano non fa scadere la '
      'richiesta in corso', () {
    fakeAsync((async) {
      final slow = _SlowShuffleApi();
      api = slow;
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        }
      };
      mount(async);
      emitShuffled(async, shuffled: true);
      slow.shuffleGate = Completer<void>();
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      async.elapse(PartyQueueEditor.shuffleSettleTimeout * 3);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off'],
          reason: 'la risposta non è ancora arrivata: niente scadenza');
      expect(announced(), isEmpty);

      slow.shuffleGate!.complete();
      async.flushMicrotasks();
      expect(announced(), ['ShuffleMode']);
      unawaited(editor().setShuffle(false));
      async.flushMicrotasks();
      expect(api.calls, ['shuffle off'],
          reason: 'il tempo per la coda nuova conta dalla risposta');
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

  group('aggiunta (spec H §8.3)', () {
    final film = testItem(id: 'm9', name: 'Alien', year: 1979);
    JellyfinItem episode(String id, int index) => testItem(
        id: id,
        name: 'E$index',
        kind: ItemKind.episode,
        seriesId: 's2',
        seriesName: 'Dark',
        index: index,
        seasonIndex: 1);

    /// La coda del server con [added] dopo il titolo in corso (o in fondo):
    /// gli elementi di prima tengono i loro id (p1…p4, come in `mount`), solo
    /// i nuovi ne hanno di nuovi (n0, n1…). [minute]: l'ordine degli
    /// aggiornamenti.
    PlayQueue withAdded(List<String> added,
        {required bool next, int minute = 5}) {
      const before = ['e3', 'e4', 'e5', 'e6'];
      final old = [
        for (var i = 0; i < before.length; i++)
          PlayQueueEntry(itemId: before[i], playlistItemId: 'p${i + 1}'),
      ];
      final fresh = [
        for (var i = 0; i < added.length; i++)
          PlayQueueEntry(itemId: added[i], playlistItemId: 'n$i'),
      ];
      return PlayQueue(
        reason: next ? 'QueueNext' : 'Queue',
        lastUpdate: DateTime.utc(2026, 9, 30, 10, minute),
        entries: next
            ? [...old.take(2), ...fresh, ...old.skip(2)]
            : [...old, ...fresh],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: false,
      );
    }

    test('riproduci dopo: manda, annuncia, aspetta la conferma, "Hai…"', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: true)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add-next m9']);
        expect(announced(), ['QueueNext']);
        expect(notices.hiddenMineCalls, [PartyNoticeKind.queuedNext]);
        expect(notices.mineItemIds, [
          ['m9'],
        ]);
        expect(notices.renewed, [PartyNoticeKind.queuedNext],
            reason: 'l\'eco dura quanto l\'attesa della conferma');
        expect(notices.renewedItemIds, [
          ['m9'],
        ]);
        expect(outcome, isNull, reason: 'aspetta la coda del server');

        emit(async, withAdded(['m9'], next: true));
        expect(outcome, PartyQueueAddOutcome.added);
        expect(notices.shown.last.kind, PartyNoticeKind.queuedNext);
        expect(notices.shown.last.mine, isTrue);
        expect(notices.shown.last.title, 'Alien');
        finish(async);
      });
    });

    test('nessuna conferma in 4 s: rifiutata; l\'eco resta per una conferma '
        'tardiva', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9']);
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, PartyQueueAddOutcome.rejected);
        expect(notices.shown.last.kind, PartyNoticeKind.queueRejected);
        expect(notices.forgotten, isEmpty);
        expect(
            notices.renewed, [PartyNoticeKind.queued, PartyNoticeKind.queued]);
        expect(notices.renewedItemIds, [
          ['m9'],
          ['m9'],
        ]);
        expect(notices.renewedWindows, [null, PartyNotices.lateAddEchoWindow]);
        finish(async);
      });
    });

    test('conferma arrivata dopo il rifiuto (avvisi veri): solo "Non '
        'aggiunto…", nessun "Aggiunto…" anonimo', () {
      fakeAsync((async) {
        final library = FakeLibraryApi()..itemsById['m9'] = film;
        final shown = <PartyNotice>[];
        mount(async, library: library, shown: shown);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, PartyQueueAddOutcome.rejected);
        // La coda del server arriva 6 s dopo la risposta.
        async.elapse(const Duration(seconds: 2));
        emit(async, withAdded(['m9'], next: false));
        async.elapse(PartyNotices.showFor * 2);
        expect([for (final notice in shown) (notice.kind, notice.mine)],
            [(PartyNoticeKind.queueRejected, true)]);
        expect(library.itemsByIdsCalls, isEmpty);
        finish(async);
      });
    });

    test('un altro aggiunge mentre la nostra aspetta (avvisi veri): il suo '
        'avviso c\'è, e la nostra è "Hai…"', () {
      fakeAsync((async) {
        final library = FakeLibraryApi()
          ..itemsById['m9'] = film
          ..itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
        final shown = <PartyNotice>[];
        mount(async, library: library, shown: shown);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        // Arrival di un altro, prima della nostra coda.
        final others = withAdded(['m2'], next: false, minute: 4);
        emit(async, others);
        expect(outcome, isNull);
        // Nessun annuncio dal plugin: l'avviso esce senza nome.
        async.elapse(PartyNotices.attributionWait);
        // Poi la nostra, con Arrival già dentro.
        emit(
            async,
            PlayQueue(
              reason: 'Queue',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
              entries: [
                ...others.entries,
                const PlayQueueEntry(itemId: 'm9', playlistItemId: 'n9'),
              ],
              playingIndex: 1,
              startPosition: Duration.zero,
              isPlaying: false,
            ));
        expect(outcome, PartyQueueAddOutcome.added);
        async.elapse(PartyNotices.showFor * 3);
        expect([
          for (final notice in shown) (notice.kind, notice.mine, notice.title)
        ], [
          (PartyNoticeKind.queued, false, 'Arrival'),
          (PartyNoticeKind.queued, true, 'Alien'),
        ]);
        finish(async);
      });
    });

    test('una coda di un altro (altri titoli) non conferma', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        emit(async, withAdded(['zz'], next: false));
        expect(outcome, isNull);
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, PartyQueueAddOutcome.rejected);
        finish(async);
      });
    });

    test('tutti già in coda: niente richiesta, niente avviso', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([testItem(id: 'e5')], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.alreadyQueued);
        expect(api.calls, isEmpty);
        expect(notices.shown, isEmpty);
        finish(async);
      });
    });

    test('coda piena: avviso, niente richiesta', () {
      fakeAsync((async) {
        mount(async);
        emit(
            async,
            testSeriesQueue(
                itemIds: [for (var i = 0; i < 100; i++) 'x$i'],
                playingIndex: 0,
                lastUpdate: DateTime.utc(2026, 9, 30, 10, 1)));
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.full);
        expect(api.calls, isEmpty);
        expect(notices.shown.last.kind, PartyNoticeKind.queueFull);
        finish(async);
      });
    });

    test('tagliata dal tetto: "Aggiunti 2 episodi su 3"', () {
      fakeAsync((async) {
        mount(async);
        // 98 titoli: posto per 2.
        final full = [for (var i = 0; i < 98; i++) 'x$i'];
        emit(
            async,
            testSeriesQueue(
                itemIds: full,
                playingIndex: 0,
                lastUpdate: DateTime.utc(2026, 9, 30, 10, 1)));
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([episode('d1', 1), episode('d2', 2), episode('d3', 3)],
                next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add d1,d2']);
        emit(
            async,
            PlayQueue(
              reason: 'Queue',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
              entries: [
                for (var i = 0; i < 98; i++)
                  PlayQueueEntry(itemId: full[i], playlistItemId: 'p${i + 1}'),
                const PlayQueueEntry(itemId: 'd1', playlistItemId: 'n1'),
                const PlayQueueEntry(itemId: 'd2', playlistItemId: 'n2'),
              ],
              playingIndex: 0,
              startPosition: Duration.zero,
              isPlaying: false,
            ));
        expect(outcome, PartyQueueAddOutcome.added);
        final notice = notices.shown.last;
        expect(notice.kind, PartyNoticeKind.queuePartial);
        expect((notice.count, notice.total, notice.series), (2, 3, 'Dark'));
        finish(async);
      });
    });

    test('due aggiunte uguali insieme: la seconda non rimanda gli stessi', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? first;
        PartyQueueAddOutcome? second;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => first = value));
        unawaited(editor()
            .add([film], next: true)
            .then((value) => second = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9']);
        expect(second, PartyQueueAddOutcome.alreadyQueued);
        expect(first, isNull, reason: 'aspetta la conferma');
        emit(async, withAdded(['m9'], next: false));
        expect(first, PartyQueueAddOutcome.added);
        expect(notices.shown, hasLength(1), reason: 'un solo "Hai aggiunto"');
        finish(async);
      });
    });

    test('richiesta fallita: "Non riuscito", eco dimenticata', () {
      fakeAsync((async) {
        mount(async);
        api.error = const ServerUnreachableException();
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.failed);
        expect(notices.shown.last.kind, PartyNoticeKind.queueFailed);
        expect(notices.forgotten, [PartyNoticeKind.queued]);
        expect(notices.forgottenItemIds, [
          ['m9'],
        ]);
        expect(notices.renewed, isEmpty);
        expect(announced(), isEmpty);
        finish(async);
      });
    });

    test('richiesta fallita: gli id tornano liberi, si può riprovare', () {
      fakeAsync((async) {
        mount(async);
        api.error = const ServerUnreachableException();
        unawaited(editor().add([film], next: false));
        async.flushMicrotasks();
        api.error = null;
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9', 'add m9']);
        emit(async, withAdded(['m9'], next: false));
        expect(outcome, PartyQueueAddOutcome.added);
        finish(async);
      });
    });

    test('la coda nuova arriva prima della risposta HTTP: confermata lo '
        'stesso', () {
      fakeAsync((async) {
        final slow = _SlowQueueApi();
        api = slow;
        api.onCall = (call) {
          if (call.startsWith('join')) {
            events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
          }
        };
        mount(async);
        slow.queueGate = Completer<void>();
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9']);
        expect(announced(), isEmpty, reason: 'la risposta non è arrivata');

        emit(async, withAdded(['m9'], next: false));
        expect(outcome, isNull, reason: 'la richiesta è ancora in corso');
        slow.queueGate!.complete();
        async.flushMicrotasks();
        expect(outcome, PartyQueueAddOutcome.added);
        expect(announced(), ['Queue']);
        expect(notices.shown.last.kind, PartyNoticeKind.queued);
        finish(async);
      });
    });

    test('un titolo già visto si riaggiunge: lo conferma la voce nuova', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([testItem(id: 'e3')], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add e3'],
            reason: 'e3 è già visto: si può riaggiungere');
        // La coda con il solo e3 di prima (p1) non conferma niente.
        emit(async, withAdded(const [], next: false, minute: 4));
        expect(outcome, isNull);
        // Con la voce nuova (n0, ancora e3) sì.
        emit(async, withAdded(['e3'], next: false));
        expect(outcome, PartyQueueAddOutcome.added);
        expect(notices.shown.last.kind, PartyNoticeKind.queued);
        finish(async);
      });
    });

    test('dopo un rifiuto gli id non restano in attesa: si può riprovare', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? first;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => first = value));
        async.flushMicrotasks();
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(first, PartyQueueAddOutcome.rejected);

        PartyQueueAddOutcome? second;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => second = value));
        async.flushMicrotasks();
        expect(api.calls, ['add m9', 'add m9']);
        emit(async, withAdded(['m9'], next: false));
        expect(second, PartyQueueAddOutcome.added);
        finish(async);
      });
    });

    test('uscita dal gruppo durante l\'attesa: nessun avviso di rifiuto', () {
      fakeAsync((async) {
        mount(async);
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([film], next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        unawaited(container.read(watchPartySessionProvider.notifier).leave());
        async.flushMicrotasks();
        async.elapse(PartyQueueEditor.addConfirmTimeout);
        expect(outcome, isNotNull, reason: 'l\'attesa è finita');
        expect(notices.shown, isEmpty);
        finish(async);
      });
    });

    test('un solo episodio su più voluti: "Aggiunto 1 episodio su 3"', () {
      fakeAsync((async) {
        mount(async);
        // 99 titoli: posto per 1.
        final full = [for (var i = 0; i < 99; i++) 'x$i'];
        emit(
            async,
            testSeriesQueue(
                itemIds: full,
                playingIndex: 0,
                lastUpdate: DateTime.utc(2026, 9, 30, 10, 1)));
        PartyQueueAddOutcome? outcome;
        unawaited(editor()
            .add([episode('d1', 1), episode('d2', 2), episode('d3', 3)],
                next: false)
            .then((value) => outcome = value));
        async.flushMicrotasks();
        expect(api.calls, ['add d1']);
        emit(
            async,
            PlayQueue(
              reason: 'Queue',
              lastUpdate: DateTime.utc(2026, 9, 30, 10, 5),
              entries: [
                for (var i = 0; i < 99; i++)
                  PlayQueueEntry(itemId: full[i], playlistItemId: 'p${i + 1}'),
                const PlayQueueEntry(itemId: 'd1', playlistItemId: 'n1'),
              ],
              playingIndex: 0,
              startPosition: Duration.zero,
              isPlaying: false,
            ));
        expect(outcome, PartyQueueAddOutcome.added);
        final notice = notices.shown.last;
        expect(notice.kind, PartyNoticeKind.queuePartial);
        expect((notice.count, notice.total, notice.series), (1, 3, 'Dark'));
        finish(async);
      });
    });
  });
}

/// `FakeSyncPlayApi` con la risposta di `queue` in attesa di [queueGate].
class _SlowQueueApi extends FakeSyncPlayApi {
  Completer<void>? queueGate;

  @override
  Future<void> queue(List<String> itemIds, {required bool next}) async {
    await super.queue(itemIds, next: next);
    await queueGate?.future;
  }
}

/// `FakeSyncPlayApi` con la risposta di `shuffle` in attesa di [shuffleGate].
class _SlowShuffleApi extends FakeSyncPlayApi {
  Completer<void>? shuffleGate;

  @override
  Future<void> setShuffleMode({required bool shuffle}) async {
    await super.setShuffleMode(shuffle: shuffle);
    await shuffleGate?.future;
  }
}
