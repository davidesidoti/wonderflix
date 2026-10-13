import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeSocialApi social;
  late FakeSocialAvailability availability;

  setUp(() {
    library = FakeLibraryApi();
    social = FakeSocialApi();
    availability = FakeSocialAvailability(SocialFeatures.none);
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: homeOverrides(
            library: library, availability: availability, social: social),
        retry: (_, _) => null,
      );

  Future<HomeLayout> layout(ProviderContainer c) {
    c.listen(homeLayoutProvider, (_, _) {});
    return c.read(homeLayoutProvider.future);
  }

  Future<HomeRowContent> row(ProviderContainer c) {
    const key = (kind: HomeRowKind.friendsWatched, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    return c.read(homeRowProvider(key).future);
  }

  const on = SocialFeatures(friends: true, friendsActivity: true);

  test('senza la funzione: riga non disponibile e nessuna chiamata', () async {
    availability = FakeSocialAvailability(const SocialFeatures(friends: true));
    final result = await layout(container());
    expect(result.visible, isNot(contains(HomeRowKind.friendsWatched)));
    expect(social.calls, isNot(contains('friendsWatched')));
    expect(
        homeRowGate(HomeRowKind.friendsWatched, const SocialFeatures(),
            seerrAccount: false),
        HomeRowGate.friendsActivityOff);
  });

  test('con la funzione: la riga c\'è, dopo Consigliati per te', () async {
    availability = FakeSocialAvailability(const SocialFeatures(
        friends: true, recommendations: true, friendsActivity: true));
    final visible = (await layout(container())).visible;
    expect(visible.indexOf(HomeRowKind.friendsWatched),
        visible.indexOf(HomeRowKind.recommended) + 1);
  });

  test('l\'ordine del plugin, senza i titoli che Jellyfin non dà', () async {
    availability = FakeSocialAvailability(on);
    library.itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
    social.friendsWatchedList = [
      testFriendsWatched('m2', ['Luca']),
      testFriendsWatched('gone', ['Luca']),
      testFriendsWatched('m1', ['Marta', 'Luca']),
    ];
    final content = await row(container()) as FriendsWatchedRowContent;
    expect(content.titles.map((t) => t.item.id), ['m2', 'm1']);
    expect(content.titles.last.by.map((w) => w.name), ['Marta', 'Luca']);
  });

  test('errore del plugin: la riga è in errore (e quindi nascosta)', () async {
    availability = FakeSocialAvailability(on);
    social.nextFailure = SocialFailure.network;
    await expectLater(row(container()), throwsA(anything));
  });

  testWidgets('la card dice chi l\'ha visto', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: HomeRowView(
          kind: HomeRowKind.friendsWatched,
          content: FriendsWatchedRowContent([
            FriendsWatchedItem(
                item: testItem(id: 'm1', name: 'Dune'),
                by: testFriendsWatched('m1', ['Luca', 'Marta', 'Sara']).by),
          ]),
          animateEntrance: false,
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
      ],
    );
    await tester.pump();
    expect(find.text('Visti dagli amici'), findsOneWidget);
    expect(find.text('Visto da Luca e altri 2'), findsOneWidget);
  });
}
