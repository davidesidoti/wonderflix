import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/update/update_controller.dart';
import 'package:wonderflix/features/update/update_gate.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeUpdateController controller;

  Future<ProviderContainer> pumpGate(WidgetTester tester, UpdateState state,
      {MotionLevel motion = MotionLevel.reduced}) async {
    controller = FakeUpdateController(state);
    await pumpApp(tester, const UpdateGate(child: Text('app')),
        motion: motion,
        overrides: [updateControllerProvider.overrideWith(() => controller)]);
    return ProviderScope.containerOf(tester.element(find.text('app')));
  }

  /// `playerActiveProvider` aggiorna lo stato in un microtask: il primo `pump`
  /// lo esegue, il secondo ricostruisce con il nuovo valore.
  Future<void> pumpPlayerState(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  final installer = File('setup.exe');

  testWidgets('nessun aggiornamento: solo l\'app', (tester) async {
    await pumpGate(tester, const UpdateState());
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Riavvia ora'), findsNothing);
  });

  testWidgets('download in corso (facoltativo): ancora niente barra',
      (tester) async {
    await pumpGate(tester, UpdateState(release: testRelease(), progress: 0.3));
    expect(find.text('Riavvia ora'), findsNothing);
  });

  testWidgets('pronto: barra con novità, "Riavvia ora" e "Più tardi"',
      (tester) async {
    await pumpGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    expect(find.text('Aggiornamento pronto: WonderFlix 0.2.0'), findsOneWidget);
    expect(find.text('Più veloce'), findsNothing);

    await tester.tap(find.text('Novità'));
    await tester.pump();
    expect(find.text('Più veloce'), findsOneWidget);

    await tester.tap(find.text('Riavvia ora'));
    await tester.pump();
    expect(controller.installs, 1);

    await tester.tap(find.text('Più tardi'));
    await tester.pump();
    // La barra scende in dissolvenza (`fast` con le animazioni ridotte):
    // sparisce a dissolvenza finita.
    await tester.pumpAndSettle();
    expect(find.text('Riavvia ora'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('completa: a download finito la barra sale dal basso',
      (tester) async {
    await pumpGate(tester, UpdateState(release: testRelease(), progress: 0.3),
        motion: MotionLevel.full);
    controller.emit(UpdateState(release: testRelease(), installer: installer));
    await tester.pump();
    Offset slide() => tester
        .widget<SlideTransition>(find
            .ancestor(
                of: find.text('Riavvia ora'),
                matching: find.byType(SlideTransition))
            .first)
        .position
        .value;
    expect(slide().dy, greaterThan(0));
    await tester.pumpAndSettle();
    expect(slide(), Offset.zero);
  });

  testWidgets('mai durante la riproduzione: la barra compare alla fine',
      (tester) async {
    final container = await pumpGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    container.read(playerActiveProvider.notifier).enter();
    await pumpPlayerState(tester);
    // La barra già visibile scende in dissolvenza: sparisce a fine uscita.
    await tester.pumpAndSettle();
    expect(find.text('Riavvia ora'), findsNothing);

    container.read(playerActiveProvider.notifier).leave();
    await pumpPlayerState(tester);
    expect(find.text('Riavvia ora'), findsOneWidget);
  });

  testWidgets('obbligatorio in download: schermata bloccante con avanzamento',
      (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            progress: 0.4));
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsOneWidget);
    expect(find.text('Download in corso… 40%'), findsOneWidget);
    expect(find.text('Più veloce'), findsOneWidget);
    // FilledButton.icon crea una sottoclasse: find.byType non la trova.
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Aggiorna ora'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
    // L'app sotto non riceve clic.
    expect(
        tester.widget<IgnorePointer>(find.ancestor(
            of: find.text('app'), matching: find.byType(IgnorePointer)).first).ignoring,
        isTrue);
  });

  testWidgets('obbligatorio pronto: "Aggiorna ora" installa', (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            installer: installer));
    await tester.tap(find.text('Aggiorna ora'));
    await tester.pump();
    expect(controller.installs, 1);
  });

  testWidgets('obbligatorio pronto: Invio installa (pulsante già a fuoco)',
      (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            installer: installer));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.installs, 1);
  });

  testWidgets('obbligatorio: a download finito Invio installa', (tester) async {
    final release = testRelease(minVersion: '0.2.0');
    await pumpGate(
        tester, UpdateState(release: release, mandatory: true, progress: 0.5));
    controller.emit(
        UpdateState(release: release, mandatory: true, installer: installer));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.installs, 1);
  });

  testWidgets('obbligatorio fallito: messaggio e "Riprova"', (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            failed: true));
    expect(find.text('Download non riuscito. Controlla la connessione e riprova.'),
        findsOneWidget);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(controller.retries, 1);
  });

  testWidgets('obbligatorio durante la riproduzione: arriva alla fine del video',
      (tester) async {
    final container = await pumpGate(tester, const UpdateState());
    container.read(playerActiveProvider.notifier).enter();
    await pumpPlayerState(tester);
    controller.emit(UpdateState(
        release: testRelease(minVersion: '0.2.0'),
        mandatory: true,
        installer: installer));
    await tester.pump();
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsNothing);

    container.read(playerActiveProvider.notifier).leave();
    await pumpPlayerState(tester);
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsOneWidget);
  });

  /// Come in `app.dart`: `UpdateGate` nel `builder` di `MaterialApp.router`,
  /// sopra il `Navigator` (niente `Overlay`).
  Future<void> pumpRouterGate(WidgetTester tester, UpdateState state) async {
    controller = FakeUpdateController(state);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => const Text('app')),
    ]);
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [updateControllerProvider.overrideWith(() => controller)],
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => UpdateGate(child: child!),
      ),
    ));
    await tester.pump();
  }

  testWidgets('nel builder di MaterialApp.router: barra funzionante',
      (tester) async {
    await pumpRouterGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Aggiornamento pronto: WonderFlix 0.2.0'), findsOneWidget);

    await tester.tap(find.text('Novità'));
    await tester.pump();
    expect(find.text('Più veloce'), findsOneWidget);

    await tester.tap(find.text('Riavvia ora'));
    await tester.pump();
    expect(controller.installs, 1);

    await tester.tap(find.text('Più tardi'));
    await tester.pump();
    // La barra scende in dissolvenza (`fast` con le animazioni ridotte):
    // sparisce a dissolvenza finita.
    await tester.pumpAndSettle();
    expect(find.text('Riavvia ora'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nel builder di MaterialApp.router: schermata bloccante',
      (tester) async {
    await pumpRouterGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            installer: installer));
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsOneWidget);
    expect(find.text('Più veloce'), findsOneWidget);

    await tester.tap(find.text('Aggiorna ora'));
    await tester.pump();
    expect(controller.installs, 1);

    controller.emit(UpdateState(
        release: testRelease(minVersion: '0.2.0'),
        mandatory: true,
        failed: true));
    await tester.pump();
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(controller.retries, 1);
    expect(tester.takeException(), isNull);
  });
}
