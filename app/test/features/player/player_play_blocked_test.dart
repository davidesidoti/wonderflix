import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/playback_service.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/player/player_screen.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/player/player_volume.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeVideoEngine engine;
  late FakePlayerWindow window;

  setUp(() {
    engine = FakeVideoEngine()..engineTracks = testEngineTracks;
    window = FakePlayerWindow();
  });

  /// Il player aperto sopra la Home, col dito ([touch]) o col mouse.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required bool touch,
    required Size surfaceSize,
  }) async {
    final playback = FakePlaybackApi();
    final library = FakeLibraryApi()
      ..itemsById['e4'] = testItem(
        id: 'e4',
        name: 'Pilot',
        kind: ItemKind.episode,
        seriesName: 'Breaking Bad',
        seriesId: 's1',
        index: 4,
        seasonIndex: 1,
      );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/play/:id',
          builder: (context, state) => PlayerScreen(
            args: (
              itemId: state.pathParameters['id']!,
              start: playerStartFrom(state.uri),
              party: null,
            ),
          ),
        ),
      ],
    );
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: surfaceSize,
      touch: touch,
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        playbackApiProvider.overrideWithValue(playback),
        playbackServiceProvider.overrideWithValue(
          PlaybackService(
            api: playback,
            serverUrl: testServerUrl,
            authorization: () => 'MediaBrowser Token="t1"',
          ),
        ),
        videoEngineFactoryProvider.overrideWithValue(() => engine),
        playerWindowProvider.overrideWithValue(window),
        mediaSessionProvider.overrideWithValue(FakeMediaSession()),
        playerSettingsProvider.overrideWith(
          () => FakePlayerSettings(const PlayerSettings()),
        ),
        playerVolumeProvider.overrideWith(() => FakePlayerVolume(100)),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
  }

  /// Smonta l'app e lascia scadere i timer (report di fine, attese).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets(
    'avvio rifiutato: compare Tocca per riprodurre, il tocco chiama play e '
    'lo strato sparisce',
    (tester) async {
      engine.blockNextPlay();
      await pumpPlayer(tester, touch: true, surfaceSize: const Size(844, 390));
      expect(engine.playing, isFalse);
      expect(find.text(l.playerTapToPlay), findsOneWidget);
      expect('play'.allMatches(engine.calls.join(' ')).length, 1);

      await tester.tap(find.text(l.playerTapToPlay));
      await tester.pumpAndSettle();
      expect(engine.playing, isTrue);
      expect('play'.allMatches(engine.calls.join(' ')).length, 2);
      expect(find.text(l.playerTapToPlay), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets('avvio riuscito: niente Tocca per riprodurre', (tester) async {
    await pumpPlayer(tester, touch: true, surfaceSize: const Size(844, 390));
    expect(engine.playing, isTrue);
    expect(find.text(l.playerTapToPlay), findsNothing);
    await unmount(tester);
  });
}
