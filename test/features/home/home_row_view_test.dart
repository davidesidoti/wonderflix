import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  Future<void> pumpRow(WidgetTester tester, HomeRowKind kind,
      HomeRowContent content,
      {SocialFeatures features = SocialFeatures.none}) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
              body: HomeRowView(
                  kind: kind, content: content, animateEntrance: false))),
      GoRoute(
          path: '/collection/:id',
          builder: (_, state) => Text('saga ${state.pathParameters['id']}')),
      GoRoute(
          path: '/item/:id',
          builder: (_, state) => Text('scheda ${state.pathParameters['id']}')),
      GoRoute(
          path: '/tmdb/:type/:id',
          builder: (_, state) => Text(
              'seerr ${state.pathParameters['type']} ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ]);
    await tester.pump();
  }

  testWidgets('saga: il clic apre la pagina della saga', (tester) async {
    await pumpRow(
        tester,
        HomeRowKind.continueSaga,
        SagasRowContent([
          SagaProgress(
              saga: testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
              next: testItem(id: 'm2', name: 'Matrix Reloaded'),
              watched: 1),
        ]));
    expect(find.text('Matrix · 1 di 2 visti'), findsOneWidget);
    await tester.tap(find.text('Matrix Reloaded'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('serie in arrivo nella libreria: la scheda', (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingSeries,
        UpcomingSeriesRowContent([testEpisode(jellyfinSeriesId: 's1')]));
    await tester.tap(find.text('The Bear'));
    await tester.pumpAndSettle();
    expect(find.text('scheda s1'), findsOneWidget);
  });

  testWidgets('serie in arrivo fuori dalla libreria: Seerr, se c\'è',
      (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingSeries,
        UpcomingSeriesRowContent([testEpisode()]),
        features: const SocialFeatures(requests: true));
    await tester.tap(find.text('The Bear'));
    await tester.pumpAndSettle();
    expect(find.text('seerr tv 136315'), findsOneWidget);
  });

  testWidgets('film in arrivo senza Seerr: non si clicca', (tester) async {
    await pumpRow(tester, HomeRowKind.upcomingMovies,
        UpcomingMoviesRowContent([testUpcomingMovie()]));
    await tester.tap(find.text('Hope'));
    await tester.pumpAndSettle();
    expect(find.textContaining('seerr'), findsNothing);
    expect(find.text('Hope'), findsOneWidget);
  });

  testWidgets('richiesta: la pagina Seerr del titolo', (tester) async {
    await pumpRow(tester, HomeRowKind.requests,
        RequestsRowContent([testMediaRequest(id: 1, type: RequestMediaType.movie)]));
    await tester.tap(find.text('Dune - Parte due'));
    await tester.pumpAndSettle();
    expect(find.text('seerr movie 693001'), findsOneWidget);
  });
}
