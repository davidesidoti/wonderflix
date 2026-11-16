import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/upcoming_week.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  final now = DateTime(2026, 11, 15, 22);

  // 17: un episodio; 18: un film; 20: tre uscite; 23: due. Sette in tutto.
  final episodes = [
    testEpisode(
      season: 2,
      episode: 8,
      airDate: DateTime(2026, 11, 17, 21),
      jellyfinSeriesId: 's1',
    ),
    testEpisode(
      seriesName: 'Andor',
      season: 1,
      episode: 3,
      last: 5,
      airDate: DateTime(2026, 11, 20, 9),
    ),
    testEpisode(seriesName: 'Severance', airDate: DateTime(2026, 11, 20, 18)),
    testEpisode(
      seriesName: 'Nessuna immagine',
      airDate: DateTime(2026, 11, 23, 10),
      tmdbId: null,
      backdropUrl: null,
    ),
  ];
  final movies = [
    testUpcomingMovie(digitalRelease: DateTime.utc(2026, 11, 18)),
    testUpcomingMovie(
      title: 'Dune',
      tmdbId: 7,
      digitalRelease: DateTime.utc(2026, 11, 20),
    ),
    testUpcomingMovie(
      jellyfinItemId: 'm9',
      title: 'Heat',
      tmdbId: 8,
      digitalRelease: DateTime.utc(2026, 11, 23),
    ),
  ];

  Future<void> pumpWeek(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    SocialFeatures features = SocialFeatures.none,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: UpcomingWeek(
              episodes: episodes,
              movies: movies,
              animateEntrance: false,
            ),
          ),
        ),
        GoRoute(
          path: '/calendar',
          builder: (_, state) => Text('calendario ${state.uri.query}'),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (_, state) => Text('scheda ${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/tmdb/:type/:id',
          builder: (_, state) => Text(
            'seerr ${state.pathParameters['type']} ${state.pathParameters['id']}',
          ),
        ),
      ],
    );
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: size,
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(features),
        ),
      ],
    );
    await tester.pump();
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('i giorni in ordine, le note e i codici', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester);
      final xs = [
        for (final d in ['17', '18', '20', '23'])
          tester.getTopLeft(find.text(d)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(find.text('dopodomani'), findsOneWidget);
      expect(colorOf(tester, 'dopodomani'), WfColors.gold);
      expect(colorOf(tester, '17'), WfColors.gold);
      expect(colorOf(tester, '18'), WfColors.cream);
      expect(find.text('domani'), findsNothing);
      expect(find.text('mar nov'), findsOneWidget); // il 17
      final day20 = find.byKey(const ValueKey('upcoming-day-2026-11-20'));
      expect(
        find.descendant(
          of: day20,
          matching: find.byKey(const Key('upcoming-entry')),
        ),
        findsNWidgets(3),
      );
      expect(find.text('S2:E8'), findsOneWidget);
      expect(find.text('S1:E3–E5'), findsOneWidget);
      expect(find.textContaining('S02'), findsNothing);
      expect(find.text('Film, in digitale'), findsNWidgets(3));
      expect(find.text('In arrivo'), findsOneWidget);
      expect(find.text('7 uscite'), findsOneWidget);
    });
  });

  testWidgets('il titolo apre il calendario sulla settimana', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester);
      await tester.tap(find.byKey(const Key('row-title-link')));
      await tester.pumpAndSettle();
      expect(find.text('calendario view=week'), findsOneWidget);
    });
  });

  testWidgets('episodio in libreria: la scheda', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester);
      await tester.tap(find.text('The Bear'));
      await tester.pumpAndSettle();
      expect(find.text('scheda s1'), findsOneWidget);
    });
  });

  testWidgets('film con Seerr: la pagina Seerr', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester, features: const SocialFeatures(requests: true));
      await tester.tap(find.text('Hope'));
      await tester.pumpAndSettle();
      expect(find.text('seerr movie 1058424'), findsOneWidget);
    });
  });

  testWidgets('film in libreria: la scheda, anche con Seerr', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester, features: const SocialFeatures(requests: true));
      await tester.scrollUntilVisible(
        find.text('Heat'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Heat'));
      await tester.pumpAndSettle();
      expect(find.text('scheda m9'), findsOneWidget);
    });
  });

  testWidgets('film senza Seerr: non si clicca', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester);
      await tester.tap(find.text('Hope'));
      await tester.pumpAndSettle();
      expect(find.textContaining('seerr'), findsNothing);
    });
  });

  testWidgets('uscita senza immagine: il riquadro vuoto e il testo', (
    tester,
  ) async {
    await withClock(Clock.fixed(now), () async {
      await pumpWeek(tester);
      await tester.scrollUntilVisible(
        find.text('Nessuna immagine'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final entry = find.ancestor(
        of: find.text('Nessuna immagine'),
        matching: find.byKey(const Key('upcoming-entry')),
      );
      expect(
        find.descendant(of: entry, matching: find.byType(ImagePlaceholder)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  for (final (size, width) in [
    (const Size(1280, 800), 236.0),
    (const Size(390, 780), 200.0),
  ]) {
    testWidgets('colonne da $width a ${size.width.toInt()}, senza overflow', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        await pumpWeek(tester, size: size);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('upcoming-day-2026-11-17')))
              .width,
          width,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
