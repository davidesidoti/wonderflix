import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/startup/splash_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

// Lo spinner dello splash gira sempre: niente pumpAndSettle.
void main() {
  testWidgets('completa: il logo compare e il riflesso passa una volta',
      (tester) async {
    await pumpApp(tester, const SplashScreen(), motion: MotionLevel.full);
    final logo = find.byKey(const Key('splash-logo'));
    double opacity() => tester
        .widget<Opacity>(
            find.ancestor(of: logo, matching: find.byType(Opacity)).first)
        .opacity;
    expect(opacity(), lessThan(1));
    expect(find.byKey(const Key('splash-sheen')), findsOneWidget);
    await tester.pump(splashIntroDuration);
    await tester.pump();
    expect(opacity(), 1);
  });

  testWidgets('ridotta: logo fermo, nessun riflesso', (tester) async {
    await pumpApp(tester, const SplashScreen());
    expect(find.byKey(const Key('splash-sheen')), findsNothing);
    final fades = tester.widgetList<Opacity>(find.ancestor(
        of: find.byKey(const Key('splash-logo')),
        matching: find.byType(Opacity)));
    expect(fades.every((f) => f.opacity == 1), isTrue);
  });

  group('splash lento', () {
    late FakeSessionController fake;

    Future<void> pumpSplash(WidgetTester tester, ProfileBook book) async {
      fake = FakeSessionController(const SessionStarting());
      await pumpApp(tester, const SplashScreen(), overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        profilesProvider
            .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
      ]);
    }

    testWidgets('dopo 10 s: il profilo che si apre e "Cambia profilo"',
        (tester) async {
      await pumpSplash(
          tester, const ProfileBook().upsert(testProfile(name: 'Mario')));

      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Apro il profilo di Mario…'), findsNothing);
      expect(find.text('Cambia profilo'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Apro il profilo di Mario…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Cambia profilo'));
      await tester.pump();
      expect(fake.backToProfilesCalls, 1);
    });

    testWidgets('il profilo è l\'ultimo usato', (tester) async {
      final book = const ProfileBook()
          .upsert(testProfile(name: 'Mario'))
          .upsert(testProfile(userId: 'u2', name: 'Luigi'))
          .withLast('u2');
      await pumpSplash(tester, book);
      await tester.pump(splashSlowAfter);
      expect(find.text('Apro il profilo di Luigi…'), findsOneWidget);
    });

    testWidgets('profilo senza nome', (tester) async {
      await pumpSplash(
          tester, const ProfileBook().upsert(testProfile(name: '')));
      await tester.pump(splashSlowAfter);
      expect(find.text('Apro il profilo…'), findsOneWidget);
    });

    testWidgets('senza profili niente testo né pulsante', (tester) async {
      await pumpSplash(tester, const ProfileBook());
      await tester.pump(const Duration(seconds: 11));
      expect(find.textContaining('Apro il profilo'), findsNothing);
      expect(find.text('Cambia profilo'), findsNothing);
    });
  });
}
