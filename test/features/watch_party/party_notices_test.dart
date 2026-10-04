import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
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

  test('sessioni in più di un membro: né entrate né uscite', () {
    fakeAsync((async) {
      // Luigi ha due sessioni: il server lo elenca una volta sola.
      api
        ..onCall = (call) {
          if (call.startsWith('join')) {
            events.add(SyncPlayGroupUpdated(GroupJoined(
                'g1', testGroup(participants: ['Mario', 'Luigi']))));
          }
        }
        ..groupInfo = testGroup(participants: ['Mario', 'Luigi']);
      mount(async);
      emit(async, const UserLeft('g1', 'Luigi'));
      expect(current(), isNull);
      emit(async, const UserJoined('g1', 'Luigi'));
      expect(current(), isNull);
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

  test('mia azione senza avviso: niente pillola, ma l\'eco resta registrata',
      () {
    fakeAsync((async) {
      mount(async);
      notices().mine(PartyNoticeKind.paused, show: false);
      expect(current(), isNull);
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current(), isNull, reason: 'è l\'eco della mia pausa');
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

  test('gruppo in attesa all\'ingresso: la ripresa è senza aspettare', () {
    fakeAsync((async) {
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(
              GroupJoined('g1', testGroup(state: GroupState.waiting))));
        }
      };
      mount(async);
      emit(async, const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      expect(current()?.kind, PartyNoticeKind.forcedResume);
      finish(async);
    });
  });

  test('titolo arrivato dopo un altro cambio o dopo l\'uscita: nessun avviso',
      () {
    fakeAsync((async) {
      library
        ..itemsById['e6'] = testItem(
            id: 'e6',
            name: 'And the Bag\'s in the River',
            kind: ItemKind.episode,
            seriesName: 'Breaking Bad',
            index: 6,
            seasonIndex: 1)
        ..delay = const Duration(seconds: 1);
      mount(async);
      emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 1,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
      async.elapse(const Duration(milliseconds: 500));
      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 2,
                  reason: 'NextItem',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 6))));
      async.elapse(const Duration(milliseconds: 600));
      expect(current(), isNull, reason: 'il gruppo è già su e6');
      async.elapse(const Duration(milliseconds: 500));
      expect(current()?.title, 'S1:E6 · And the Bag\'s in the River');
      async.elapse(PartyNotices.showFor);

      emit(
          async,
          PlayQueueUpdate(
              'g1',
              testSeriesQueue(
                  playingIndex: 1,
                  reason: 'NewPlaylist',
                  lastUpdate: DateTime.utc(2026, 9, 30, 10, 7))));
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.elapse(const Duration(seconds: 2));
      expect(current(), isNull, reason: 'fuori dal gruppo');
      finish(async);
    });
  });

  test('la sessione si ricostruisce: gli avvisi continuano', () {
    fakeAsync((async) {
      mount(async);
      container.invalidate(watchPartySessionProvider);
      container.read(watchPartySessionProvider);
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      async.flushMicrotasks();
      emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      expect(current()?.kind, PartyNoticeKind.paused);
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

  test('il server ci toglie (il gruppo può esserci ancora): "non sei più"',
      () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupLeft('g1'));
      expect(current()?.kind, PartyNoticeKind.removed);
      finish(async);
    });
  });

  test('NotInGroup: "non sei più nel watch party"', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const NotInGroup(''));
      expect(current()?.kind, PartyNoticeKind.removed);
      finish(async);
    });
  });

  test('gruppo sparito al rientro: "terminato"', () {
    fakeAsync((async) {
      mount(async);
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(const GroupDoesNotExist('')));
        }
      };
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(current()?.kind, PartyNoticeKind.ended);
      finish(async);
    });
  });

  group('nome di chi agisce (spec E §8)', () {
    test('annuncio arrivato prima: l\'avviso ha subito il nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('annuncio arrivato dopo: l\'avviso lo aspetta', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current(), isNull, reason: 'aspetta il nome');
        async.elapse(const Duration(milliseconds: 120));
        notices().attribute(testActionEvent(PartyAction.pause));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('nessun annuncio entro 300 ms: avviso senza nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(
            PartyNotices.attributionWait - const Duration(milliseconds: 1));
        expect(current(), isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('canale spento: nessuna attesa', () {
      fakeAsync((async) {
        mount(async);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('annuncio più vecchio di 2 s: non vale', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        async.elapse(PartyNotices.announcementLifetime +
            const Duration(milliseconds: 1));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('l\'annuncio si consuma: un secondo avviso uguale resta senza nome',
        () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        expect(current()?.name, 'Luigi');
        async.elapse(PartyNotices.showFor);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('ripresa forzata e salto prendono il nome dall\'annuncio giusto', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async,
            const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
        notices().attribute(
            testActionEvent(PartyAction.unpause, id: 'a1', userName: 'Peach'));
        emit(async,
            const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
        expect(current()?.kind, PartyNoticeKind.forcedResume);
        expect(current()?.name, 'Peach');

        async.elapse(PartyNotices.showFor);
        const position = Duration(minutes: 32, seconds: 10);
        seekCommand(async, position);
        notices().attribute(
            testActionEvent(PartyAction.seek, id: 'a2', position: position));
        emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
        expect(current()?.kind, PartyNoticeKind.seeked);
        expect(current()?.name, 'Luigi');
        expect(current()?.position, position);
        finish(async);
      });
    });

    test('episodio successivo: nome e titolo', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().attribute(testActionEvent(PartyAction.nextItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    playingIndex: 1,
                    reason: 'NextItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nextEpisode);
        expect(current()?.name, 'Luigi');
        expect(current()?.title, isNotNull);
        finish(async);
      });
    });

    test('canale spento con avvisi in attesa: escono subito senza nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current(), isNull);
        notices().setAttribution(false);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('le proprie azioni non aspettano, e l\'eco non produce avvisi', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().mine(PartyNoticeKind.paused);
        expect(current()?.mine, isTrue);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        async.elapse(PartyNotices.showFor);
        expect(current(), isNull);
        finish(async);
      });
    });
  });

  group('coda del party (spec H §10)', () {
    test('precedente: titolo dell\'episodio e nome dall\'annuncio giusto', () {
      fakeAsync((async) {
        library.itemsById['e4'] = testItem(
            id: 'e4',
            name: 'Pilot',
            kind: ItemKind.episode,
            seriesName: 'Breaking Bad',
            index: 4,
            seasonIndex: 1);
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue(playingIndex: 1)));
        notices()
          ..attribute(testActionEvent(PartyAction.nextItem, userName: 'Mario'))
          ..attribute(testActionEvent(PartyAction.previousItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'PreviousItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.previousItem);
        expect(current()?.title, 'S1:E4 · Pilot');
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('salto dalla coda: "Si guarda" con il nome di SetCurrentItem', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices()
          ..attribute(testActionEvent(PartyAction.newQueue, userName: 'Mario'))
          ..attribute(testActionEvent(PartyAction.setCurrentItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    playingIndex: 1,
                    reason: 'SetCurrentItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nowWatching);
        expect(current()?.title, 'S1:E5 · Cat\'s in the Bag',
            reason: 'il salto nomina l\'episodio, come successivo e precedente');
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('successivo verso un film: il titolo del film, non l\'anno', () {
      fakeAsync((async) {
        mount(async);
        emit(async,
            PlayQueueUpdate('g1', testSeriesQueue(itemIds: ['e4', 'm2'])));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'm2'],
                    playingIndex: 1,
                    reason: 'NextItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nextEpisode);
        expect(current()?.title, 'Arrival');
        finish(async);
      });
    });

    test('ordine casuale degli altri: acceso, poi spento', () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        async.elapse(PartyNotices.showFor);
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
        expect(current()?.kind, PartyNoticeKind.shuffleOff);
        finish(async);
      });
    });

    test('ordine casuale: il nome dall\'annuncio ShuffleMode', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().attribute(testActionEvent(PartyAction.shuffleMode));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('il mio ordine casuale: nessun avviso, anche con l\'eco dopo 3 s',
        () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().mine(PartyNoticeKind.shuffleOn, show: false);
        async.elapse(const Duration(milliseconds: 3500));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current(), isNull);
        finish(async);
      });
    });

    test('prima coda già mescolata, rimozioni e spostamenti: nessun avviso',
        () {
      fakeAsync((async) {
        mount(async);
        emit(async,
            PlayQueueUpdate('g1', testSeriesQueue(shuffled: true)));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'e5'],
                    shuffled: true,
                    reason: 'RemoveItems',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'e5'],
                    shuffled: true,
                    reason: 'MoveItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 10))));
        expect(current(), isNull);
        finish(async);
      });
    });

    test('prima coda dopo l\'ingresso con motivo ShuffleMode: nessun avviso',
        () {
      fakeAsync((async) {
        mount(async);
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(reason: 'ShuffleMode', shuffled: true)));
        expect(current(), isNull);
        finish(async);
      });
    });

    test('la mia eco più vecchia di 4 s non conta: l\'avviso c\'è', () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().mine(PartyNoticeKind.shuffleOn, show: false);
        async.elapse(PartyNotices.queueEchoWindow +
            const Duration(milliseconds: 500));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        finish(async);
      });
    });

    test('forget: una richiesta non riuscita non scarta il cambio di un altro',
        () {
      fakeAsync((async) {
        mount(async);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices()
          ..mine(PartyNoticeKind.shuffleOn, show: false)
          ..forget(PartyNoticeKind.shuffleOn);
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    reason: 'ShuffleMode',
                    shuffled: true,
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.shuffleOn);
        finish(async);
      });
    });

    test('rimozione che cambia il titolo in corso: subito, senza aspettare '
        'un nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    itemIds: ['e4', 'e5'],
                    playingIndex: 1,
                    reason: 'RemoveItems',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nowWatching);
        expect(current()?.title, 'Breaking Bad');
        expect(current()?.name, isNull);
        finish(async);
      });
    });
  });
}
