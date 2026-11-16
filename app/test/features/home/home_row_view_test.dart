import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
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
      for (final path in ['/requests', '/movies', '/series', '/mylist'])
        GoRoute(
            path: path,
            builder: (_, state) => Text('pagina ${state.uri}')),
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

  testWidgets('richiesta: la pagina Seerr del titolo', (tester) async {
    await pumpRow(tester, HomeRowKind.requests,
        RequestsRowContent([testMediaRequest(id: 1, type: RequestMediaType.movie)]));
    await tester.tap(find.text('Dune - Parte due'));
    await tester.pumpAndSettle();
    expect(find.text('seerr movie 693001'), findsOneWidget);
  });

  group('intestazioni (spec §9.1)', () {
    final items = ItemsRowContent(
        [testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Heat')]);
    final saga = SagasRowContent([
      SagaProgress(
          saga: testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
          next: testItem(id: 'm2', name: 'Matrix Reloaded'),
          watched: 1),
      SagaProgress(
          saga: testCollection(id: 'c2', name: 'Alien', itemIds: ['a1', 'a2']),
          next: testItem(id: 'a2', name: 'Aliens'),
          watched: 1),
    ]);
    final links = <(HomeRowKind, HomeRowContent, String, String)>[
      (
        HomeRowKind.requests,
        RequestsRowContent([
          testMediaRequest(id: 1, type: RequestMediaType.movie),
          testMediaRequest(id: 2, type: RequestMediaType.movie, title: 'Andor'),
        ]),
        'Le mie richieste',
        '/requests'
      ),
      (HomeRowKind.latestMovies, items, 'Film aggiunti di recente', '/movies'),
      (HomeRowKind.latestSeries, items, 'Serie aggiunte di recente', '/series'),
      (HomeRowKind.continueSaga, saga, 'Continua la saga', '/movies?view=sagas'),
      (HomeRowKind.myList, items, 'La mia lista', '/mylist'),
    ];
    for (final (kind, content, title, route) in links) {
      testWidgets('"$title" porta a $route, con il conteggio', (tester) async {
        await pumpRow(tester, kind, content);
        final heading = tester.widget<Text>(find.text(title));
        expect(heading.style?.fontSize, 26);
        expect(heading.style?.fontFamily, WfText.displayFamily);
        expect(find.text('2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('row-title-link')));
        await tester.pumpAndSettle();
        expect(find.text('pagina $route'), findsOneWidget);
      });
    }

    testWidgets('Consigliati per te e Visti dagli amici non sono link',
        (tester) async {
      await pumpRow(
          tester,
          HomeRowKind.recommended,
          RecommendedRowContent([
            RecommendedItem(
                item: testItem(id: 'm1', name: 'Dune'),
                from: testRecommendation('m1', [('Luca', null)]).from),
          ]));
      expect(find.text('Consigliati per te'), findsOneWidget);
      expect(find.byKey(const Key('row-title-link')), findsNothing);
      expect(find.text('Da Luca'), findsOneWidget);
      expect(tester.widget<PosterCard>(find.byType(PosterCard)).catalogStyle,
          isTrue);

      await pumpRow(
          tester,
          HomeRowKind.friendsWatched,
          FriendsWatchedRowContent([
            FriendsWatchedItem(
                item: testItem(id: 'm1', name: 'Dune'),
                by: testFriendsWatched('m1', ['Luca']).by),
          ]));
      expect(find.text('Visti dagli amici'), findsOneWidget);
      expect(find.byKey(const Key('row-title-link')), findsNothing);
    });

    testWidgets('le locandine sono quelle del catalogo', (tester) async {
      await pumpRow(tester, HomeRowKind.latestMovies, items);
      expect(
          tester
              .widgetList<PosterCard>(find.byType(PosterCard))
              .every((card) => card.catalogStyle),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
