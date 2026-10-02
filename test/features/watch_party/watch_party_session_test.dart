import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  /// Crea il container e monta la sessione. Nei test con `fakeAsync` va
  /// chiamato dentro la zona finta: gli eventi arrivano nella zona in cui la
  /// sessione si è iscritta allo stream.
  void mount() {
    container = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
    ]);
    container.listen(watchPartySessionProvider, (_, _) {});
  }

  WatchPartySession session() =>
      container.read(watchPartySessionProvider.notifier);
  WatchPartyState state() => container.read(watchPartySessionProvider);
  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Il server conferma l'ingresso appena riceve `create` o `join`.
  void serverAccepts({List<String> participants = const ['Mario']}) {
    api.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        emit(GroupJoined('g1', testGroup(participants: participants)));
      }
    };
  }

  SyncPlayCommand command(SyncPlayCommandType type,
          {DateTime? emittedAt, String group = 'g1'}) =>
      SyncPlayCommand(
        groupId: group,
        playlistItemId: 'p1',
        when: DateTime.utc(2026, 9, 30, 11),
        position: const Duration(minutes: 5),
        type: type,
        emittedAt: emittedAt ?? DateTime.utc(2026, 9, 30, 11),
      );

  test('create: nome del gruppo, conferma e coda', () async {
    mount();
    serverAccepts();
    await session().create(testItem(id: 'm1', name: 'Dune'),
        start: const Duration(minutes: 1));
    expect(api.calls, ['create Mario · Dune', 'queue m1']);
    expect(api.queues.single.start, const Duration(minutes: 1));
    expect(state().phase, WatchPartyPhase.inGroup);
    expect(state().group?.id, 'g1');
    expect(state().members, ['Mario']);
  });

  test('create per un episodio: nel nome c\'è la serie', () async {
    mount();
    serverAccepts();
    await session().create(testItem(
        id: 'e1',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad'));
    expect(api.calls.first, 'create Mario · Breaking Bad');
  });

  test('join, poi membri che entrano ed escono', () async {
    mount();
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    expect(api.calls, ['join g1']);
    expect(state().members, ['Mario', 'Luigi']);

    emit(const UserJoined('g1', 'Peach'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi', 'Peach']);

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Peach']);

    // Aggiornamenti di un altro gruppo: ignorati.
    emit(const UserJoined('g2', 'Bowser'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Peach']);
  });

  test('id dei gruppi con e senza trattini', () async {
    mount();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        emit(GroupJoined('AAAA-BBBB', testGroup(id: 'AAAA-BBBB')));
      }
    };
    await session().join('AAAA-BBBB');
    emit(const UserJoined('aaaabbbb', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi']);
  });

  test('stato del gruppo e coda; le code vecchie si scartano', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await pumpEventQueue();
    expect(state().groupState, GroupState.waiting);

    emit(PlayQueueUpdate(
        'g1', testQueue(lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(state().queue?.playing?.playlistItemId, 'p1');

    emit(PlayQueueUpdate('g1',
        testQueue(playlistItemId: 'p0', lastUpdate: DateTime.utc(2026, 9, 30, 10))));
    await pumpEventQueue();
    expect(state().queue?.playing?.playlistItemId, 'p1');
  });

  test('gruppo inesistente', () async {
    mount();
    api.onCall = (call) => emit(const GroupDoesNotExist(''));
    await expectLater(
        session().join('g9'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.groupGone)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('accesso negato', () async {
    mount();
    api.onCall = (call) => emit(const LibraryAccessDenied('g1'));
    await expectLater(
        session().join('g1'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.accessDenied)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('errore di rete', () async {
    mount();
    api.error = const ServerUnreachableException();
    await expectLater(
        session().join('g1'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(state().phase, WatchPartyPhase.none);
  });

  test('coda non impostata: si esce dal gruppo appena creato', () async {
    mount();
    api.onCall = (call) {
      if (call.startsWith('create')) {
        emit(GroupJoined('g1', testGroup()));
      }
      if (call.startsWith('queue')) throw const ServerErrorException(500);
    };
    await expectLater(
        session().create(testItem()),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(api.calls.last, 'leave');
    expect(state().phase, WatchPartyPhase.none);
  });

  test('nessuna conferma entro 10 s', () {
    fakeAsync((async) {
      mount();
      Object? error;
      unawaited(session().join('g1').catchError((Object e) {
        error = e;
      }));
      async.elapse(const Duration(seconds: 9));
      expect(error, isNull);
      expect(state().phase, WatchPartyPhase.joining);
      async.elapse(const Duration(seconds: 1));
      expect((error! as WatchPartyException).failure,
          WatchPartyFailure.timeout);
      expect(state().phase, WatchPartyPhase.none);

      // Una conferma che arriva tardi: si esce subito dal gruppo.
      emit(GroupJoined('g1', testGroup()));
      async.flushMicrotasks();
      expect(api.calls.last, 'leave');
      expect(state().phase, WatchPartyPhase.none);
    });
  });

  test('errore di rete all\'ingresso: si esce da un eventuale gruppo fantasma',
      () async {
    mount();
    api.onCall = (call) {
      if (call.startsWith('join')) throw const ServerErrorException(500);
    };
    await expectLater(
        session().join('g1'),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(api.calls, ['join g1', 'leave']);
    expect(state().phase, WatchPartyPhase.none);
  });

  test('nessuna conferma entro 10 s: si esce da un eventuale gruppo fantasma',
      () {
    fakeAsync((async) {
      mount();
      unawaited(session().join('g1').catchError((Object _) {}));
      async.elapse(WatchPartySession.joinTimeout);
      expect(api.calls, ['join g1', 'leave']);
      expect(state().phase, WatchPartyPhase.none);
    });
  });

  test('eventi di un gruppo fuori da un gruppo: si esce, al massimo ogni 30 s',
      () {
    fakeAsync((async) {
      mount();
      events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
      async.flushMicrotasks();
      expect(api.calls, ['leave']);

      emit(const UserJoined('g1', 'Luigi'));
      emit(const UserLeft('g1', 'Luigi'));
      emit(const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
      emit(PlayQueueUpdate('g1', testQueue()));
      async.elapse(const Duration(seconds: 29));
      expect(api.calls, ['leave']);

      async.elapse(const Duration(seconds: 1));
      emit(const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
      async.flushMicrotasks();
      expect(api.calls, ['leave', 'leave']);
      expect(state().phase, WatchPartyPhase.none);
    });
  });

  test('eventi di un gruppo durante l\'ingresso: nessuna uscita', () {
    fakeAsync((async) {
      mount();
      unawaited(session().join('g1').catchError((Object _) {}));
      async.flushMicrotasks();
      events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.pause)));
      emit(PlayQueueUpdate('g1', testQueue()));
      async.flushMicrotasks();
      expect(api.calls, ['join g1']);
      expect(state().phase, WatchPartyPhase.joining);
      async.elapse(WatchPartySession.joinTimeout);
    });
  });

  test('leave: una volta sola', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await session().leave();
    expect(api.calls, ['join g1', 'leave']);
    expect(state().phase, WatchPartyPhase.none);
    await session().leave();
    expect(api.calls, ['join g1', 'leave']);
  });

  test('il server ci toglie dal gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
  });

  test('comandi: solo del gruppo e non più vecchi dell\'ingresso', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final received = <SyncPlayCommand>[];
    final subscription = session().commands.listen(received.add);
    addTearDown(subscription.cancel);

    // testGroup().lastUpdatedAt = 10:00: questo è di prima.
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.pause,
        emittedAt: DateTime.utc(2026, 9, 30, 9, 59))));
    events.add(SyncPlayCommandReceived(
        command(SyncPlayCommandType.pause, group: 'g2')));
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await pumpEventQueue();
    expect(received.map((c) => c.type), [SyncPlayCommandType.unpause]);
    expect(session().lastCommand?.type, SyncPlayCommandType.unpause);
  });

  test('orologio: parte con l\'ingresso e riferisce il ping', () async {
    mount();
    serverAccepts();
    expect(session().serverClock, isNull);
    await session().join('g1');
    await pumpEventQueue();
    expect(session().serverClock?.ready, isTrue);
    expect(api.pings, isNotEmpty);
    await session().leave();
    expect(session().serverClock, isNull);
  });

  test('estimatedPosition: dalla coda o dall\'ultimo comando', () {
    fakeAsync((async) {
      mount();
      serverAccepts();
      unawaited(session().join('g1'));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), Duration.zero);

      emit(PlayQueueUpdate('g1', testQueue(start: const Duration(minutes: 7))));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), const Duration(minutes: 7));

      final now = clock.now().toUtc();
      events.add(SyncPlayCommandReceived(SyncPlayCommand(
        groupId: 'g1',
        playlistItemId: 'p1',
        when: now.subtract(const Duration(seconds: 2)),
        position: const Duration(minutes: 5),
        type: SyncPlayCommandType.unpause,
        emittedAt: DateTime.utc(2100),
      )));
      async.flushMicrotasks();
      expect(session().estimatedPosition(),
          const Duration(minutes: 5, seconds: 2));

      events.add(SyncPlayCommandReceived(SyncPlayCommand(
        groupId: 'g1',
        playlistItemId: 'p1',
        when: now,
        position: const Duration(minutes: 6),
        type: SyncPlayCommandType.pause,
        emittedAt: DateTime.utc(2100, 1, 1, 0, 0, 1),
      )));
      async.flushMicrotasks();
      expect(session().estimatedPosition(), const Duration(minutes: 6));
      unawaited(session().leave());
      async.flushMicrotasks();
    });
  });

  test('logout: si torna a nessun gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await container.read(sessionControllerProvider.notifier).logout();
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
    expect(session().startLag, isNull);
  });

  test('ritardo alla ripartenza: uno per tutto il watch party', () async {
    mount();
    serverAccepts();
    expect(session().startLag, isNull);
    await session().join('g1');
    final startLag = session().startLag;
    expect(startLag, isNotNull);
    startLag!.record(const Duration(milliseconds: 400));

    // Episodio nuovo: la stima resta.
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 1,
            reason: 'NextItem',
            lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(session().startLag, same(startLag));
    expect(session().startLag!.value, const Duration(milliseconds: 200));

    await session().leave();
    expect(session().startLag, isNull);
    await session().join('g1');
    expect(session().startLag, isNot(same(startLag)));
    expect(session().startLag!.value, Duration.zero);

    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(session().startLag, isNull);
  });

  test('create con la coda di una serie', () async {
    mount();
    serverAccepts();
    await session().create(
        testItem(
            id: 'e4',
            name: 'Pilot',
            kind: ItemKind.episode,
            seriesName: 'Breaking Bad'),
        queue: ['e4', 'e5', 'e6']);
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5,e6']);
  });

  test('setQueue: nel gruppo solo la nuova coda; fuori nessuna richiesta',
      () async {
    mount();
    await session().setQueue(['m2']);
    expect(api.calls, isEmpty);

    serverAccepts();
    await session().join('g1');
    await session().setQueue(['m2'], start: const Duration(minutes: 2));
    expect(api.calls, ['join g1', 'queue m2']);
    expect(api.queues.single.start, const Duration(minutes: 2));
  });

  test('setQueue con un errore di rete', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    api.error = const ServerUnreachableException();
    await expectLater(
        session().setQueue(['m2']),
        throwsA(isA<WatchPartyException>().having(
            (e) => e.failure, 'failure', WatchPartyFailure.network)));
    expect(state().inGroup, isTrue);
  });

  test('nextItem: solo se c\'è un elemento dopo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    expect(await session().nextItem('p1'), isFalse);

    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await pumpEventQueue();
    expect(state().hasNext, isTrue);
    expect(state().nextEntry?.itemId, 'e5');
    expect(await session().nextItem('p1'), isTrue);
    expect(api.calls.last, 'next p1');

    emit(PlayQueueUpdate(
        'g1',
        testSeriesQueue(
            playingIndex: 2, lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
    await pumpEventQueue();
    expect(state().hasNext, isFalse);
    expect(await session().nextItem('p3'), isFalse);
    expect(api.calls.last, 'next p1');
  });

  test('nextItem da un elemento non più in riproduzione: niente', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(PlayQueueUpdate(
        'g1', testSeriesQueue(playingIndex: 1, reason: 'NextItem')));
    await pumpEventQueue();
    api.calls.clear();
    // Il player di e4 (p1) chiede il successivo quando il gruppo è già su e5.
    expect(await session().nextItem('p1'), isFalse);
    expect(api.calls, isEmpty);
    expect(await session().nextItem('p2'), isTrue);
    expect(api.calls, ['next p2']);
  });

  test('nextItem con la richiesta fallita: false, niente annuncio', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    await pumpEventQueue();
    api.error = const ServerUnreachableException();
    expect(await session().nextItem('p1'), isFalse);
    expect(api.calls.last, 'next p1');
  });

  test('membri: lo stesso utente con due sessioni compare una volta', () async {
    mount();
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    emit(const UserJoined('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi']);

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi'],
        reason: 'Luigi ha ancora una sessione nel gruppo');

    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario']);
  });

  test('updates: solo gli aggiornamenti del nostro gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    emit(const UserJoined('g1', 'Luigi'));
    emit(const UserJoined('g2', 'Bowser'));
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
    emit(PlayQueueUpdate('g1', testSeriesQueue()));
    // Più vecchia della precedente: scartata e non inoltrata.
    emit(PlayQueueUpdate(
        'g1', testSeriesQueue(lastUpdate: DateTime.utc(2026, 9, 30, 9))));
    await pumpEventQueue();
    expect(updates.map((u) => u.runtimeType),
        [UserJoined, GroupStateUpdate, PlayQueueUpdate]);
  });

  test('membri riletti dal server: entrate e uscite solo se cambiano i nomi',
      () async {
    mount();
    // Luigi ha due sessioni: il server lo elenca una volta sola.
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);
    api.groupInfo = testGroup(participants: ['Mario', 'Luigi']);

    // Esce una delle due sessioni di Luigi: resta nel gruppo.
    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(api.groupRequests, ['g1']);
    expect(state().members, ['Mario', 'Luigi']);
    expect(updates, isEmpty);

    api.groupInfo = testGroup(participants: ['Mario', 'Luigi', 'Peach']);
    emit(const UserJoined('g1', 'Peach'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi', 'Peach']);
    expect(updates.single, isA<UserJoined>());

    // Luigi riapre una sessione: era già nel gruppo.
    emit(const UserJoined('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario', 'Luigi', 'Peach']);
    expect(updates, hasLength(1));
  });

  test('membri non riletti (errore di rete): vale l\'aggiornamento locale',
      () async {
    mount();
    serverAccepts(participants: ['Mario', 'Luigi']);
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);
    api.error = const ServerUnreachableException();
    emit(const UserLeft('g1', 'Luigi'));
    await pumpEventQueue();
    expect(state().members, ['Mario']);
    expect(updates.single, isA<UserLeft>());
  });

  test('comandi e aggiornamenti continuano se la sessione si ricostruisce',
      () async {
    mount();
    serverAccepts();
    final updates = <GroupUpdate>[];
    final commands = <SyncPlayCommand>[];
    final subscriptions = [
      session().updates.listen(updates.add),
      session().commands.listen(commands.add),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
    container.invalidate(watchPartySessionProvider);
    expect(state().phase, WatchPartyPhase.none);

    await session().join('g1');
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.pause)));
    await pumpEventQueue();
    expect(updates, hasLength(1));
    expect(commands, hasLength(1));
  });

  test('riconnessione: si rientra nello stesso gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    expect(state().rejoins, 0);

    serverAccepts(participants: ['Mario', 'Luigi']);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['join g1', 'join g1']);
    expect(state().inGroup, isTrue);
    expect(state().rejoins, 1);
    expect(state().members, ['Mario', 'Luigi']);
  });

  test('prima connessione, o fuori da un gruppo: nessun rientro', () async {
    mount();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, isEmpty);

    serverAccepts();
    await session().join('g1');
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['join g1']);
  });

  test('gruppo sparito durante il rientro: fuori, e l\'avviso lo sa',
      () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    api.onCall = (call) {
      if (call.startsWith('join')) emit(const GroupDoesNotExist(''));
    };
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
    expect(updates.whereType<GroupDoesNotExist>(), hasLength(1));
  });

  test('il server ci toglie: l\'aggiornamento arriva agli avvisi', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
    expect(updates.whereType<GroupLeft>(), hasLength(1));
  });

  test('uscita nostra: nessun aggiornamento agli avvisi', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await session().leave();
    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(updates, isEmpty);
  });

  test('esclusione dall\'attesa: richiesta solo quando cambia, finisce con '
      'il gruppo', () async {
    mount();
    // Fuori da un gruppo: niente.
    await session().ignoreWait();
    expect(api.calls, isEmpty);
    expect(session().ignoringWait, isFalse);

    serverAccepts();
    await session().join('g1');
    await session().ignoreWait();
    await session().ignoreWait();
    expect(session().ignoringWait, isTrue);
    await session().stopIgnoringWait();
    await session().stopIgnoringWait();
    expect(session().ignoringWait, isFalse);
    expect(api.calls, ['join g1', 'ignore-wait true', 'ignore-wait false']);

    await session().ignoreWait();
    await session().leave();
    expect(session().ignoringWait, isFalse);
    await session().stopIgnoringWait();
    expect(api.calls, [
      'join g1',
      'ignore-wait true',
      'ignore-wait false',
      'ignore-wait true',
      'leave',
    ]);
  });

  test('esclusione dall\'attesa: il server ci toglie, non vale più', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await session().ignoreWait();
    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(session().ignoringWait, isFalse);
  });

  test('rientro dopo una riconnessione: l\'esclusione dall\'attesa si rimanda '
      '(il server ricrea il membro)', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    await session().ignoreWait();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls,
        ['join g1', 'ignore-wait true', 'join g1', 'ignore-wait true']);
    expect(session().ignoringWait, isTrue);
    expect(state().rejoins, 1);
  });

  test(
      'rientro: NotInGroup e GroupLeft di richieste partite prima del Join '
      'non chiudono il watch party', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    api.onCall = (call) {
      if (call.startsWith('join')) {
        // Risposte a un Ping e a un Ready mandati prima del Join.
        emit(const NotInGroup(''));
        emit(const GroupLeft('g1'));
        emit(GroupJoined('g1', testGroup(participants: ['Mario', 'Luigi'])));
      }
    };
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(state().inGroup, isTrue);
    expect(state().rejoins, 1);
    expect(state().members, ['Mario', 'Luigi']);
    expect(api.calls, ['join g1', 'join g1']);
    expect(updates, isEmpty);

    // Rientrati: un NotInGroup adesso vuol dire che il server ci ha tolto.
    emit(const NotInGroup(''));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
  });

  test('due riconnessioni di fila: due rientri', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    events.add(const ServerConnected(true));
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['join g1', 'join g1', 'join g1']);
    expect(state().inGroup, isTrue);
    expect(state().rejoins, 2);
  });

  test('rientro non inviato (errore di rete): un NotInGroup dopo chiude',
      () async {
    mount();
    serverAccepts();
    await session().join('g1');
    api.onCall = (call) {
      if (call.startsWith('join')) throw const ServerUnreachableException();
    };
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(state().inGroup, isTrue);

    emit(const NotInGroup(''));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
  });

  test(
      'rientro senza risposta entro 10 s: si smette di aspettarlo; una '
      'conferma tardiva vale ancora', () {
    fakeAsync((async) {
      mount();
      serverAccepts();
      unawaited(session().join('g1'));
      async.flushMicrotasks();
      api.onCall = null;
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      emit(const NotInGroup(''));
      async.flushMicrotasks();
      expect(state().inGroup, isTrue, reason: 'si aspetta il rientro');

      async.elapse(WatchPartySession.rejoinTimeout);
      emit(GroupJoined('g1', testGroup()));
      async.flushMicrotasks();
      expect(state().rejoins, 1);

      emit(const NotInGroup(''));
      async.flushMicrotasks();
      expect(state().phase, WatchPartyPhase.none);
    });
  });

  test('rientro senza risposta entro 10 s: poi un NotInGroup chiude', () {
    fakeAsync((async) {
      mount();
      serverAccepts();
      unawaited(session().join('g1'));
      async.flushMicrotasks();
      api.onCall = null;
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      async.elapse(WatchPartySession.rejoinTimeout);
      expect(state().inGroup, isTrue);
      emit(const NotInGroup(''));
      async.flushMicrotasks();
      expect(state().phase, WatchPartyPhase.none);
    });
  });
}
