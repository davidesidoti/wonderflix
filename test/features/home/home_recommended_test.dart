import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/recommendations/recommendation_dismissals.dart';
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

  Future<HomeRowContent> row(ProviderContainer c, HomeRowKind kind) {
    final key = (kind: kind, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    return c.read(homeRowProvider(key).future);
  }

  test('senza la funzione: riga non disponibile e nessuna chiamata', () async {
    availability = FakeSocialAvailability(const SocialFeatures(friends: true));
    final c = container();
    final result = await layout(c);
    expect(result.visible, isNot(contains(HomeRowKind.recommended)));
    expect(social.calls, isNot(contains('recommendations')));
    expect(
        homeRowGate(HomeRowKind.recommended, const SocialFeatures(), seerrAccount: false),
        HomeRowGate.recommendationsOff);
  });

  test('con la funzione: la riga c\'è, dopo Prossimi episodi', () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    final result = await layout(container());
    final visible = result.visible;
    expect(visible.indexOf(HomeRowKind.recommended),
        visible.indexOf(HomeRowKind.nextUp) + 1);
  });

  test('la riga tiene l\'ordine del plugin e salta i titoli che Jellyfin non dà',
      () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    library.itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
    social.recommendationsList = [
      testRecommendation('m2', [('Luca', 'da vedere')]),
      testRecommendation('gone', [('Luca', null)]),
      testRecommendation('m1', [('Marta', null)]),
    ];
    final content = await row(container(), HomeRowKind.recommended)
        as RecommendedRowContent;
    expect(content.titles.map((t) => t.item.id), ['m2', 'm1']);
    expect(content.titles.first.from.single.name, 'Luca');
    expect(library.itemsByIdsCalls.single, ['m2', 'gone', 'm1']);
  });

  test('errore del plugin: la riga è in errore (e non si vede)', () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    social.nextFailure = SocialFailure.network;
    final c = container();
    final key = (kind: HomeRowKind.recommended, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    await expectLater(c.read(homeRowProvider(key).future), throwsA(isA<SocialException>()));
  });

  /// Monta la riga con i titoli [ids] (m1 "Dune: Parte Due", gli altri "Arrival").
  Future<void> pumpRecommended(WidgetTester tester, List<String> ids) {
    final titles = [
      for (final id in ids)
        RecommendedItem(
          item: id == 'm1'
              ? testItem(id: 'm1')
              : testItem(id: id, name: 'Arrival'),
          from: testRecommendation(
              id, [('Luca', 'da vedere'), ('Marta', null)]).from,
        ),
    ];
    return pumpApp(
      tester,
      Scaffold(
          body: HomeRowView(
              kind: HomeRowKind.recommended,
              content: RecommendedRowContent(titles),
              animateEntrance: false)),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
      ],
    );
  }

  testWidgets('card: chi l\'ha consigliata, messaggi e Non mi interessa', (tester) async {
    await pumpRecommended(tester, ['m1']);
    await tester.pump();
    expect(find.text('Consigliati per te'), findsOneWidget);
    expect(find.text('Da Luca e Marta'), findsOneWidget);
  });

  testWidgets('Non mi interessa: la card sparisce subito', (tester) async {
    await pumpRecommended(tester, ['m1', 'm2']);
    await tester.pump();
    await tester.runAsync(() => ProviderScope.containerOf(
            tester.element(find.byType(HomeRowView)))
        .read(recommendationDismissalsProvider.notifier)
        .dismiss('m1'));
    await tester.pump();
    expect(social.calls, contains('dismiss m1'));
    expect(find.text('Dune: Parte Due'), findsNothing); // m1
    expect(find.text('Arrival'), findsOneWidget); // m2
  });

  testWidgets('Non mi interessa non riuscito: la card torna', (tester) async {
    await pumpRecommended(tester, ['m1']);
    await tester.pump();
    social.nextFailure = SocialFailure.network;
    final ok = await tester.runAsync(() => ProviderScope.containerOf(
            tester.element(find.byType(HomeRowView)))
        .read(recommendationDismissalsProvider.notifier)
        .dismiss('m1'));
    await tester.pump();
    expect(ok, isFalse);
    expect(find.text('Dune: Parte Due'), findsOneWidget);
  });
}
