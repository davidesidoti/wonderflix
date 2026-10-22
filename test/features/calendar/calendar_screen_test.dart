import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/calendar/calendar_navigation.dart';
import 'package:wonderflix/features/calendar/calendar_screen.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/states.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

/// Mezzogiorno del 22 ottobre 2026: il mese di oggi è ottobre.
final _now = DateTime(2026, 10, 22, 12);

void main() {
  late FakeHomeApi api;
  late FakeSocialAvailability availability;

  setUp(() {
    api = FakeHomeApi();
    availability = FakeSocialAvailability(
      const SocialFeatures(calendar: true, requests: true),
    );
  });

  /// Monta la pagina in un router con `/calendar`, come nell'app: il mese
  /// sta nell'indirizzo e la pagina si rifà a ogni indirizzo nuovo.
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    String location = '/calendar',
    bool admin = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/calendar',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: Scaffold(
              body: CalendarScreen(
                key: ValueKey(state.uri.toString()),
                month: parseCalendarMonth(state.uri.queryParameters['month']),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Scaffold(body: Text('scheda ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) => Scaffold(
            body: Text(
              'tmdb ${state.pathParameters['type']} '
              '${state.pathParameters['tmdbId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          serverEventsBindingProvider.overrideWithValue(null),
          imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333)),
          ),
          homeApiProvider.overrideWithValue(api),
          socialAvailabilityProvider.overrideWith(() => availability),
          sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser)),
          ),
          isAdminProvider.overrideWithValue(admin),
        ],
        retry: (_, _) => null,
        child: MaterialApp.router(
          theme: buildWonderflixTheme(),
          locale: const Locale('it'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => WfMotionScope(
            motion: const WfMotion(MotionLevel.reduced),
            child: child!,
          ),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  String address(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// [body] con l'orologio fermo a [_now].
  Future<void> atNow(Future<void> Function() body) =>
      withClock(Clock.fixed(_now), body);

  testWidgets('ShowsTheMonthOfTodayAndAsksItsPeriod', (tester) async {
    await atNow(() async {
      await pumpScreen(tester);

      expect(find.text('CALENDARIO'), findsOneWidget);
      expect(find.text('Ottobre 2026'), findsOneWidget);
      expect(api.calendarCalls, [
        (DateTime(2026, 9, 28), DateTime(2026, 11, 9)),
      ]);
    });
  });

  testWidgets('ArrowsAndTodayChangeTheAddress', (tester) async {
    await atNow(() async {
      final router = await pumpScreen(tester);
      TextButton today() =>
          tester.widget<TextButton>(find.byKey(const Key('calendar-today')));
      expect(today().onPressed, isNull);

      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pumpAndSettle();
      expect(address(router), '/calendar?month=2026-11');
      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(today().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('calendar-today')));
      await tester.pumpAndSettle();
      expect(address(router), '/calendar?month=2026-10');

      await tester.tap(find.byKey(const Key('calendar-previous')));
      await tester.pumpAndSettle();
      expect(address(router), '/calendar?month=2026-09');
    });
  });

  testWidgets('TappingAnEntryOpensItsPage', (tester) async {
    await atNow(() async {
      api.calendarPage = CalendarPage(
        episodes: [testEpisode(jellyfinSeriesId: 'abc')],
        movies: [testUpcomingMovie(title: 'Hope', tmdbId: 456)],
      );
      final router = await pumpScreen(tester);

      await tester.tap(find.text('The Bear'));
      await tester.pumpAndSettle();
      expect(find.text('scheda abc'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hope'));
      await tester.pumpAndSettle();
      expect(find.text('tmdb movie 456'), findsOneWidget);
    });
  });

  testWidgets('OneServiceFailingShowsALine', (tester) async {
    await atNow(() async {
      api.calendarPage = CalendarPage(
        movies: [testUpcomingMovie(title: 'Hope')],
        seriesError: UpcomingError.unreachable,
      );
      await pumpScreen(tester);

      expect(find.text('Le serie non si possono caricare ora'), findsOneWidget);
      expect(find.text('Hope'), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
    });
  });

  testWidgets('OneServiceFailingShowsTheReasonToTheAdmin', (tester) async {
    await atNow(() async {
      api.calendarPage = const CalendarPage(
        moviesError: UpcomingError.unauthorized,
      );
      await pumpScreen(tester, admin: true);

      expect(
        find.text('I film non si possono caricare ora · Chiave API rifiutata'),
        findsOneWidget,
      );
    });
  });

  testWidgets('TheOnlyConfiguredServiceFailingIsAnError', (tester) async {
    await atNow(() async {
      api.calendarPage = const CalendarPage(
        seriesError: UpcomingError.unreachable,
        moviesError: UpcomingError.notConfigured,
      );
      await pumpScreen(tester);

      expect(find.byType(ErrorView), findsOneWidget);
    });
  });

  testWidgets('NotConfiguredIsSilent', (tester) async {
    await atNow(() async {
      api.calendarPage = CalendarPage(
        episodes: [testEpisode()],
        moviesError: UpcomingError.notConfigured,
      );
      await pumpScreen(tester);

      expect(find.text('I film non si possono caricare ora'), findsNothing);
      expect(find.byType(ErrorView), findsNothing);
      expect(find.text('The Bear'), findsOneWidget);
    });
  });

  testWidgets('EveryServiceFailingIsAnError', (tester) async {
    await atNow(() async {
      api.calendarPage = const CalendarPage(
        seriesError: UpcomingError.unreachable,
        moviesError: UpcomingError.unauthorized,
      );
      await pumpScreen(tester);

      expect(find.byType(ErrorView), findsOneWidget);
      expect(api.calendarCalls, hasLength(1));

      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(api.calendarCalls, hasLength(2));
    });
  });

  testWidgets('AnApiErrorIsAnErrorWithRetry', (tester) async {
    await atNow(() async {
      api.calendarError = const ServerUnreachableException();
      await pumpScreen(tester);

      expect(find.byType(ErrorView), findsOneWidget);
      api.calendarError = null;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsNothing);
      expect(api.calendarCalls, hasLength(2));
    });
  });

  testWidgets('AnEmptyMonthSaysSo', (tester) async {
    await atNow(() async {
      // Solo un giorno fuori dal mese, nella griglia: il mese resta vuoto.
      api.calendarPage = CalendarPage(
        movies: [testUpcomingMovie(digitalRelease: DateTime.utc(2026, 11, 3))],
      );
      await pumpScreen(tester);

      expect(find.text('Nessuna uscita in questo mese'), findsOneWidget);
    });
  });

  testWidgets('AMonthWithEntriesIsNotEmpty', (tester) async {
    await atNow(() async {
      api.calendarPage = CalendarPage(movies: [testUpcomingMovie()]);
      await pumpScreen(tester);

      expect(find.text('Nessuna uscita in questo mese'), findsNothing);
    });
  });

  testWidgets('GoesHomeWhenTheFeatureDisappears', (tester) async {
    await atNow(() async {
      final router = await pumpScreen(tester);

      availability.set(const SocialFeatures(known: true));
      await tester.pumpAndSettle();
      expect(address(router), '/home');
    });
  });
}
