import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/ratings/rating_round_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/library_fakes.dart';
import '../../support/rating_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

/// Il party: gruppo `g1`, coda `p1, p2` con `p1` in riproduzione.
class _Party extends WatchPartySession {
  @override
  WatchPartyState build() => WatchPartyState(
        phase: WatchPartyPhase.inGroup,
        group: testGroup(),
        queue: testSeriesQueue(itemIds: const ['e4', 'e5']),
      );

  void exit() => state = const WatchPartyState();
}

const _on = SocialFeatures(friends: true, parties: true, ratings: true);

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;
  late _Party party;
  late ProviderContainer container;

  ProviderContainer make() {
    party = _Party();
    final c = ProviderContainer(
      overrides: [
        ...socialTestOverrides(api, events: events.stream, features: _on),
        watchPartySessionProvider.overrideWith(() => party),
        libraryApiProvider.overrideWithValue(
            FakeLibraryApi()..itemsById['e4'] = testItem(id: 'e4')),
      ],
      retry: (_, _) => null,
    );
    c.listen(ratingRoundProvider, (_, _) {});
    return c;
  }

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    container = make();
  });

  tearDown(() async {
    container.dispose();
    await events.close();
  });

  final e4 = testItem(id: 'e4', name: 'Pilot');

  RatingRoundController controller() =>
      container.read(ratingRoundProvider.notifier);
  RatingRoundView? view() => container.read(ratingRoundProvider);

  Future<void> open([RatingRound? round]) async {
    api.openRoundResult = round ?? testRatingRound();
    api.rounds['g1'] = api.openRoundResult;
    await controller()
        .open(groupId: 'g1', item: e4, playlistItemId: 'p1');
  }

  Future<void> push(Map<String, dynamic> state) async {
    events.add(ratingRoundUpdatedReceived(state));
    await pumpEventQueue();
  }

  List<String> voteCalls() =>
      api.calls.where((c) => c.startsWith('round-vote')).toList();

  RatingRound voted({int rev = 2}) => testRatingRound(rev: rev, mine: {
        'Score': 8,
        'Comment': 'Bello'
      }, voters: [
        {'UserId': 'u1', 'Name': 'Mario', 'Status': 'Voted'},
        {'UserId': 'u2', 'Name': 'Luigi', 'Status': 'Waiting'},
      ]);

  test('l\'apertura applica lo stato e ricorda l\'elemento della coda',
      () async {
    await open(testRatingRound(mine: {'Score': 7}));

    expect(api.calls.last, 'round-open g1 e4');
    expect(view()!.holdsQueue('p1'), isTrue);
    expect(view()!.holdsQueue('p2'), isFalse);
    expect(view()!.draft, 7);
    expect(view()!.source!.id, 'e4');
  });

  test('due aperture per lo stesso elemento: una sola chiamata', () async {
    api.openRoundResult = testRatingRound();
    final first =
        controller().open(groupId: 'g1', item: e4, playlistItemId: 'p1');
    final second =
        controller().open(groupId: 'g1', item: e4, playlistItemId: 'p1');
    await first;
    await second;
    await controller().open(groupId: 'g1', item: e4, playlistItemId: 'p1');

    expect(api.calls.where((c) => c.startsWith('round-open')), hasLength(1));
  });

  test('apertura non riuscita: nessuna votazione', () async {
    for (final failure in [SocialFailure.forbidden, SocialFailure.network]) {
      api.nextFailure = failure;
      await controller().open(groupId: 'g1', item: e4, playlistItemId: 'p1');
      expect(view(), isNull);
    }
  });

  test('solo gli stati più recenti della stessa votazione contano', () async {
    await open(testRatingRound(rev: 2));

    await push(ratingRoundJson(rev: 1, canReveal: true));
    expect(view()!.round.rev, 2);
    expect(view()!.round.canReveal, isFalse);

    await push(ratingRoundJson(groupId: 'g9', rev: 5));
    expect(view()!.round.rev, 2);

    await push(ratingRoundJson(rev: 3));
    expect(view()!.round.rev, 3);

    // Un'altra votazione sostituisce la prima, anche con un Rev più basso.
    await push(ratingRoundJson(itemId: 'm2', rev: 1));
    expect(view()!.round.itemId, 'm2');

    await push(ratingRoundJson(itemId: 'm2', rev: 1, endsAt: '2026-10-20T22:00:00Z'));
    expect(view()!.round.endsAt, DateTime.utc(2026, 10, 20, 22));
  });

  test('un avviso arrivato prima dell\'apertura si adotta', () async {
    await push(ratingRoundJson());

    expect(view()!.playlistItemId, 'p1');
    expect(view()!.holdsQueue('p1'), isTrue);
  });

  test('voto: numero e commento, poi lo stato del plugin', () async {
    await open();
    api.rounds['g1'] = voted();

    controller().select(8);
    await controller().vote('Bello');

    expect(api.calls.last, 'round-vote g1 8 Bello');
    expect(view()!.myStatus, RatingVoterStatus.voted);
    expect(view()!.editing, isFalse);
    expect(view()!.sending, isFalse);
    expect(view()!.showsPicker, isFalse);
  });

  test('un secondo voto mentre il primo è in volo non parte', () async {
    await open();
    api.rounds['g1'] = voted();
    api.ratingGate = Completer<void>();
    controller().select(8);

    unawaited(controller().vote(null));
    await pumpEventQueue();
    unawaited(controller().vote(null));
    await pumpEventQueue();
    expect(view()!.sending, isTrue);
    expect(voteCalls(), hasLength(1));

    api.ratingGate!.complete();
    await pumpEventQueue();
    expect(view()!.sending, isFalse);
  });

  test('voto non riuscito', () async {
    await open();
    api.rounds['g1'] = voted();
    controller().select(8);

    api.nextFailure = SocialFailure.rateLimited;
    await controller().vote(null);
    expect(view()!.error, RatingSendError.tooMany);
    expect(view()!.sending, isFalse);

    api.nextFailure = SocialFailure.network;
    await controller().vote(null);
    expect(view()!.error, RatingSendError.notSaved);

    // Chiusa nel frattempo: si rilegge.
    api.rounds['g1'] = null;
    api.calls.clear();
    await controller().vote(null);
    expect(api.calls, contains('round g1'));
  });

  test('un commento vuoto parte come null', () async {
    await open();
    api.rounds['g1'] = voted();
    controller().select(5);
    await controller().vote('   ');
    expect(api.calls.last, 'round-vote g1 5 -');
  });

  test('select e step restano fra 1 e 10', () async {
    await open();

    controller().select(0);
    expect(view()!.draft, isNull);
    controller().step(1);
    expect(view()!.draft, 1);
    controller().step(-1);
    expect(view()!.draft, 1);
    controller().select(10);
    controller().step(1);
    expect(view()!.draft, 10);
    controller().select(11);
    expect(view()!.draft, 10);
  });

  test('Cambia riapre i numeri', () async {
    await open(voted());
    expect(view()!.showsPicker, isFalse);

    controller().edit();

    expect(view()!.showsPicker, isTrue);
    expect(view()!.draft, 8);
  });

  test('skip e reveal', () async {
    await open();
    api.rounds['g1'] = testRatingRound(rev: 2);

    await controller().skip();
    expect(api.calls.last, 'round-skip g1');
    await controller().reveal();
    expect(api.calls.last, 'round-reveal g1');
  });

  test('Revealed non ferma la coda e dopo 10 minuti sparisce', () {
    fakeAsync((async) {
      container.dispose();
      container = make();
      api.openRoundResult = testRatingRound();
      unawaited(controller()
          .open(groupId: 'g1', item: e4, playlistItemId: 'p1'));
      async.flushMicrotasks();
      expect(view()!.holdsQueue('p1'), isTrue);

      events.add(ratingRoundUpdatedReceived(ratingRoundJson(
          phase: 'Revealed', rev: 5, average: 7.5, results: const [])));
      async.flushMicrotasks();
      expect(view()!.holdsQueue('p1'), isFalse);
      expect(view(), isNotNull);

      async.elapse(ratingRoundKeep);
      expect(view(), isNull);
      container.dispose();
    });
  });

  test('ancora Voting 5 s dopo EndsAt: si rilegge', () {
    fakeAsync((async) {
      container.dispose();
      container = make();
      final endsAt =
          clock.now().add(const Duration(minutes: 2)).toUtc().toIso8601String();
      api.openRoundResult = testRatingRound(endsAt: endsAt);
      api.rounds['g1'] = api.openRoundResult;
      unawaited(controller()
          .open(groupId: 'g1', item: e4, playlistItemId: 'p1'));
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 2, seconds: 4));
      expect(api.calls, isNot(contains('round g1')));
      async.elapse(const Duration(seconds: 2));
      expect(api.calls.where((c) => c == 'round g1'), hasLength(1));

      // Ancora Voting con lo stesso Rev: si riprova.
      async.elapse(const Duration(seconds: 6));
      expect(api.calls.where((c) => c == 'round g1'), hasLength(2));
      container.dispose();
    });
  });

  test('rilettura fallita: si riprova', () {
    fakeAsync((async) {
      container.dispose();
      container = make();
      final endsAt =
          clock.now().add(const Duration(minutes: 2)).toUtc().toIso8601String();
      api.openRoundResult = testRatingRound(endsAt: endsAt);
      api.rounds['g1'] = api.openRoundResult;
      unawaited(controller()
          .open(groupId: 'g1', item: e4, playlistItemId: 'p1'));
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 2, seconds: 4));
      api.nextFailure = SocialFailure.network;
      async.elapse(const Duration(seconds: 2));
      expect(api.calls.where((c) => c == 'round g1'), hasLength(1));

      api.rounds['g1'] = testRatingRound(
          phase: 'Revealed', rev: 2, endsAt: endsAt);
      async.elapse(const Duration(seconds: 6));
      expect(api.calls.where((c) => c == 'round g1'), hasLength(2));
      expect(view()!.holdsQueue('p1'), isFalse);
      container.dispose();
    });
  });

  test('lo stesso stato con un voto già dato riempie il numero', () async {
    await open();
    expect(view()!.draft, isNull);

    await push(ratingRoundJson(rev: 2, mine: {'Score': 6}));

    expect(view()!.draft, 6);
  });

  test('Revealed arrivato prima del tempo: nessuna rilettura', () {
    fakeAsync((async) {
      container.dispose();
      container = make();
      final endsAt =
          clock.now().add(const Duration(minutes: 2)).toUtc().toIso8601String();
      api.openRoundResult = testRatingRound(endsAt: endsAt);
      unawaited(controller()
          .open(groupId: 'g1', item: e4, playlistItemId: 'p1'));
      async.flushMicrotasks();
      events.add(ratingRoundUpdatedReceived(
          ratingRoundJson(phase: 'Revealed', rev: 2, endsAt: endsAt)));
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 3));
      expect(api.calls, isNot(contains('round g1')));
      container.dispose();
    });
  });

  test('riconnessione: si rilegge; {} vuol dire non disponibile', () async {
    await open();
    api.rounds['g1'] = null;
    api.calls.clear();

    events.add(const ServerConnected(true));
    await pumpEventQueue();

    expect(api.calls, ['round g1']);
    expect(view()!.unavailable, isTrue);
    expect(view()!.holdsQueue('p1'), isFalse);
  });

  test('uscendo dal gruppo la votazione sparisce', () async {
    await open();
    party.exit();
    await pumpEventQueue();
    expect(view(), isNull);
  });

  test('con la funzione spenta la votazione sparisce', () async {
    await open();
    (container.read(socialAvailabilityProvider.notifier)
            as FakeSocialAvailability)
        .set(const SocialFeatures(friends: true, parties: true));
    await pumpEventQueue();
    expect(view(), isNull);
  });

  test('dismiss toglie la votazione', () async {
    await open();
    controller().dismiss();
    expect(view(), isNull);

    // Un avviso ritardatario della stessa votazione non la riporta.
    await push(ratingRoundJson(rev: 9));
    expect(view(), isNull);
  });
}
