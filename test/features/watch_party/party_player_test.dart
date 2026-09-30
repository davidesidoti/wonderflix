import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeVideoEngine engine;
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakeLibraryApi library;
  late ProviderContainer container;
  late GoRouter router;

  void emit(GroupUpdate update) => events.add(SyncPlayGroupUpdated(update));

  /// Home con il player del watch party aperto sopra: l'utente è già nel
  /// gruppo `g1` (Mario e Luigi), che guarda `e4` (`p1`).
  Future<void> pumpPartyPlayer(WidgetTester tester) async {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    final playback = FakePlaybackApi();
    library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      )
      ..nextEpisodes['e4'] = testItem(
          id: 'e5', name: 'Cat\'s in the Bag', kind: ItemKind.episode);
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play/:id',
        builder: (context, state) => PlayerScreen(
          key: ValueKey(state.uri.toString()),
          args: (
            itemId: state.pathParameters['id']!,
            start: playerStartFrom(state.uri),
            party: state.uri.queryParameters['party'],
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(PlaybackService(
          api: playback,
          serverUrl: testServerUrl,
          authorization: () => 'MediaBrowser Token="t1"',
        )),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        playerWindowProvider.overrideWithValue(FakePlayerWindow()),
        mediaSessionProvider.overrideWithValue(FakeMediaSession()),
        playerSettingsProvider
            .overrideWith(() => FakePlayerSettings(const PlayerSettings())),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        appConfigProvider.overrideWithValue(testAppConfig),
        imageBuilderProvider.overrideWithValue(
            (image, fit) => const ColoredBox(color: Color(0xFF333333))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
      ],
      retry: (_, _) => null,
    );
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    api.onCall = (call) {
      if (call.startsWith('join')) {
        emit(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi'])));
      }
    };
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    unawaited(router.push(playerRoute('e4', party: 'p1')));
    await tester.pumpAndSettle();
  }

  /// Smonta tutto: chiude il player, ferma l'orologio del gruppo e lascia
  /// scadere i timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    container.dispose();
    await tester.pump();
  }

  SyncPlayCommand command(SyncPlayCommandType type) {
    final now = clock.now().toUtc();
    return SyncPlayCommand(
      groupId: 'g1',
      playlistItemId: 'p1',
      when: now,
      position: Duration.zero,
      type: type,
      emittedAt: now.add(const Duration(days: 365 * 100)),
    );
  }

  testWidgets('a file aperto: Ready al gruppo, il video non parte da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(api.calls, contains('ready'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il pulsante play chiede la ripresa al gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(api.calls, contains('unpause'));
    expect(engine.calls, isNot(contains('play')));
    await finish(tester);
  });

  testWidgets('il comando del gruppo fa partire il video', (tester) async {
    await pumpPartyPlayer(tester);
    events.add(SyncPlayCommandReceived(command(SyncPlayCommandType.unpause)));
    await tester.pump();
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });

  testWidgets('distintivo con i membri e uscita dal gruppo', (tester) async {
    await pumpPartyPlayer(tester);
    expect(find.text(l.watchPartyButton(2)), findsOneWidget);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsOneWidget);
    await tester.tap(find.text(l.watchPartyLeave));
    await tester.pumpAndSettle();
    expect(api.calls, contains('leave'));
    expect(find.text('home'), findsOneWidget);
    expect(container.read(watchPartySessionProvider).inGroup, isFalse);
    await finish(tester);
  });

  testWidgets('attesa del gruppo: dopo 1 s, con "Riprendi senza aspettare"',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.watchPartyWaiting), findsOneWidget);
    await tester.tap(find.text(l.watchPartyResumeNow));
    await tester.pump();
    expect(api.calls, contains('unpause'));

    emit(const GroupStateUpdate('g1', GroupState.playing, 'Ready'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyWaiting), findsNothing);
    await finish(tester);
  });

  testWidgets('nel watch party non c\'è l\'episodio successivo',
      (tester) async {
    await pumpPartyPlayer(tester);
    await tester.pump();
    expect(find.byTooltip(l.playerNextEpisode), findsNothing);
    await finish(tester);
  });

  testWidgets('gruppo chiuso dal server: il player continua da solo',
      (tester) async {
    await pumpPartyPlayer(tester);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyButton(2)), findsNothing);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });
}
