import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/update/update_controller.dart';
import 'package:wonderflix/features/update/update_gate.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeUpdateController controller;

  Future<ProviderContainer> pumpGate(WidgetTester tester, UpdateState state) async {
    controller = FakeUpdateController(state);
    await pumpApp(tester, const UpdateGate(child: Text('app')),
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
    expect(find.text('Riavvia ora'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('mai durante la riproduzione: la barra compare alla fine',
      (tester) async {
    final container = await pumpGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    container.read(playerActiveProvider.notifier).enter();
    await pumpPlayerState(tester);
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
}
