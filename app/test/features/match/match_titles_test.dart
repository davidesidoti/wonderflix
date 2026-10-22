import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/match/match_titles.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeMatchApi match;
  late FakeLibraryApi library;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    match = FakeMatchApi();
    library = FakeLibraryApi();
    events = StreamController<ServerEvent>.broadcast();
    container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, match: true))),
        matchApiProvider.overrideWithValue(match),
        libraryApiProvider.overrideWithValue(library),
      ],
      retry: (_, _) => null,
    );
    container.listen(matchRoomProvider, (_, _) {});
    container.listen(matchTitlesProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await events.close();
  });

  Future<void> push(MatchState state) async {
    events.add(matchUpdatedReceived(state));
    await pumpEventQueue();
  }

  MatchState voting(int rev, List<String> stack) => testMatchState(
      rev: rev, phase: MatchPhase.voting, stack: stack);

  test('titlesFollowTheStack', () async {
    library.itemsById['m1'] = testItem(id: 'm1');
    library.itemsById['m3'] = testItem(id: 'm3');
    library.itemsById['m4'] = testItem(id: 'm4');
    match.rooms['r1'] = voting(1, ['m1', 'm2', 'm3']);
    await container.read(matchRoomProvider.notifier).open();
    await pumpEventQueue();

    final titles = container.read(matchTitlesProvider);
    expect(titles.keys, unorderedEquals(['m1', 'm2', 'm3']));
    expect(titles['m1']?.id, 'm1');
    expect(titles['m2'], isNull);
    expect(titles['m3']?.id, 'm3');

    await push(voting(2, ['m1', 'm2', 'm3', 'm4']));

    expect(container.read(matchTitlesProvider)['m4']?.id, 'm4');
    expect(library.itemsByIdsCalls, [
      ['m1', 'm2', 'm3'],
      ['m4'],
    ]);
  });

  test('aFailedLoadIsRetriedWithoutANewState', () async {
    library.itemsById['m1'] = testItem(id: 'm1');
    library.error = Exception('rete');
    match.rooms['r1'] = voting(1, ['m1']);
    await container.read(matchRoomProvider.notifier).open();
    await pumpEventQueue();
    expect(container.read(matchTitlesProvider), isEmpty);

    library.error = null;
    await Future<void>.delayed(matchTitlesRetryDelay * 1.5);

    expect(container.read(matchTitlesProvider)['m1']?.id, 'm1');
  });

  test('aNewRoomStartsEmpty', () async {
    library.itemsById['m1'] = testItem(id: 'm1');
    match.rooms['r1'] = voting(1, ['m1']);
    final room = container.read(matchRoomProvider.notifier);
    await room.open();
    await pumpEventQueue();
    expect(container.read(matchTitlesProvider), isNotEmpty);

    await room.leave();
    await pumpEventQueue();

    expect(container.read(matchTitlesProvider), isEmpty);
  });
}
