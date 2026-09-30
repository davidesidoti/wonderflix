import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

void main() {
  final overrides = [
    sessionControllerProvider
        .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
    // Nessun elenco dei watch party (né timer).
    watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
    syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
    watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
  ];

  Widget page() => ListView(
        key: const Key('page'),
        children: [
          for (var i = 0; i < 40; i++) SizedBox(height: 100, child: Text('riga $i')),
        ],
      );

  Future<void> pumpShell(WidgetTester tester, String location,
      {MotionLevel motion = MotionLevel.reduced}) async {
    await pumpApp(tester, AppShell(location: location, child: page()),
        overrides: overrides, motion: motion);
    await tester.pumpAndSettle();
  }

  // Il margine sotto la barra è delle pagine (vedi app_shell_router_test):
  // la shell non sposta il contenuto, così nel push/pop la pagina che esce
  // non salta.
  testWidgets('la shell non sposta il contenuto, qualunque sia la pagina',
      (tester) async {
    for (final location in ['/home', '/item/m1', '/movies', '/person/p1']) {
      await pumpShell(tester, location);
      expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 0,
          reason: location);
    }
  });

  testWidgets('la sottolineatura sta sotto la voce attiva', (tester) async {
    await pumpShell(tester, '/movies', motion: MotionLevel.full);
    final indicator = tester.getRect(find.byKey(const Key('nav-indicator')));
    final movies = tester.getRect(find.byKey(const Key('nav-/movies')));
    expect(indicator.left, closeTo(movies.left, 0.5));
    expect(indicator.width, closeTo(movies.width, 0.5));
  });

  testWidgets('nessuna voce attiva: nessuna sottolineatura', (tester) async {
    await pumpShell(tester, '/item/m1');
    expect(find.byKey(const Key('nav-indicator')), findsNothing);
  });

  testWidgets('la barra si scurisce quando la pagina scorre', (tester) async {
    await pumpShell(tester, '/movies');
    AnimatedOpacity backdrop() =>
        tester.widget<AnimatedOpacity>(find.byKey(const Key('shell-bar-backdrop')));
    expect(backdrop().opacity, 0);
    await tester.drag(find.byKey(const Key('page')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backdrop().opacity, 1);
    await tester.drag(find.byKey(const Key('page')), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(backdrop().opacity, 0);
  });

  testWidgets('voce della barra oro al passaggio del mouse', (tester) async {
    await pumpShell(tester, '/home');
    Color labelColor() =>
        tester.widget<Text>(find.text('Film')).style!.color!;
    expect(labelColor(), WfColors.cream);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Film')));
    await tester.pumpAndSettle();
    expect(labelColor(), WfColors.gold);
  });
}
