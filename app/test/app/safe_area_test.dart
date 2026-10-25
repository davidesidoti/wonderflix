import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../support/fake_session_controller.dart';
import '../support/playback_fakes.dart';
import '../support/pump_app.dart';
import '../support/social_fakes.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

const _phone = Size(390, 844);

// Tacca e barra home di un iPhone, in punti logici.
const _top = 47.0;
const _bottom = 34.0;

void main() {
  void insets(WidgetTester tester) {
    final dpr = tester.view.devicePixelRatio;
    tester.view.padding =
        FakeViewPadding(top: _top * dpr, bottom: _bottom * dpr);
    addTearDown(tester.view.resetPadding);
  }

  testWidgets(
      'aree sicure: barra in basso e controlli del player stanno dentro il padding',
      (tester) async {
    insets(tester);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: appShellBuilder,
          routes: [
            GoRoute(
                path: '/home',
                pageBuilder: (context, state) => shellPage(
                    context, state, const Text('pagina'),
                    underBar: true)),
          ],
        ),
      ],
    );
    final api = FakeSocialApi();
    await pumpAppRouter(
      tester,
      router,
      surfaceSize: _phone,
      touch: true,
      overrides: [
        ...socialTestOverrides(api,
            features: const SocialFeatures(friends: true), session: false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(SessionSignedIn(testUser))),
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(const [])),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(const Key('bottom-nav-/home'))).bottom,
        lessThanOrEqualTo(_phone.height - _bottom));
    // La barra in alto: il logo sta sotto la tacca.
    expect(tester.getRect(find.byType(Image).first).top,
        greaterThanOrEqualTo(_top));
    // La pagina sotto la barra comincia sotto la barra con la tacca.
    expect(tester.getRect(find.text('pagina')).top, greaterThanOrEqualTo(_top));

    // Altra radice: i provider della shell non servono al player.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view:
              const PlayerViewState(status: PlayerStatus.ready, playing: true),
          engine: FakeVideoEngine(),
          fullscreen: false,
          onBack: () {},
          onTogglePlay: () {},
          onSeekBy: (_) {},
          onSeekTo: (_) {},
          onVolume: (_) {},
          onToggleMute: () {},
          onToggleTracks: () {},
          onToggleFullscreen: () {},
        ),
      ),
      surfaceSize: _phone,
      touch: true,
    );
    expect(tester.getRect(find.byTooltip('Indietro')).top,
        greaterThanOrEqualTo(_top));
    // Lo sfondo sfumato arriva al bordo: i pulsanti in basso no.
    final lowest = tester
        .widgetList(find.byType(PlayerIconButton))
        .map((w) => tester.getRect(find.byWidget(w)).bottom)
        .reduce((a, b) => a > b ? a : b);
    expect(lowest, lessThanOrEqualTo(_phone.height - _bottom));
  });
}
