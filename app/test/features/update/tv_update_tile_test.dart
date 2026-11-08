import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/update/tv_update_tile.dart';
import 'package:wonderflix/features/update/update_controller.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeUpdateController controller;

  Future<void> pumpTile(WidgetTester tester, UpdateState state,
      {bool tv = true}) async {
    controller = FakeUpdateController(state);
    await pumpApp(tester, const Scaffold(body: TvUpdateTile()),
        tv: tv,
        overrides: [updateControllerProvider.overrideWith(() => controller)]);
  }

  final apk = File('WonderFlix-TV-0.2.0.apk');

  testWidgets('pronto: versione e "Aggiorna" focalizzabile', (tester) async {
    await pumpTile(tester, UpdateState(release: testRelease(), installer: apk));
    expect(find.text('WonderFlix 0.2.0 disponibile'), findsOneWidget);
    final focus = Focus.of(tester.element(find.text('Aggiorna')));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    // OK del telecomando.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(controller.installs, 1);
  });

  testWidgets('in download: la percentuale, niente pulsante', (tester) async {
    await pumpTile(tester, UpdateState(release: testRelease(), progress: 0.4));
    expect(find.text('Download in corso… 40%'), findsOneWidget);
    expect(find.text('Aggiorna'), findsNothing);
  });

  testWidgets('permesso necessario: come concederlo', (tester) async {
    await pumpTile(
        tester,
        UpdateState(
            release: testRelease(),
            installer: apk,
            installPermissionNeeded: true));
    expect(
        find.text('Consenti a WonderFlix di installare app (Impostazioni di '
            'Android → Installa app sconosciute), poi premi di nuovo Aggiorna.'),
        findsOneWidget);
    expect(find.text('Aggiorna'), findsOneWidget);
  });

  testWidgets('nessun aggiornamento: niente', (tester) async {
    await pumpTile(tester, const UpdateState());
    expect(find.textContaining('disponibile'), findsNothing);
    expect(find.text('Aggiorna'), findsNothing);
  });

  testWidgets('fuori dalla TV: niente', (tester) async {
    await pumpTile(tester, UpdateState(release: testRelease(), installer: apk),
        tv: false);
    expect(find.textContaining('disponibile'), findsNothing);
    expect(find.text('Aggiorna'), findsNothing);
  });
}
