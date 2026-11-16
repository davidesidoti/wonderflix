import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/ui/panel_header.dart';
import 'package:wonderflix/ui/shell_side_panel.dart';
import 'package:wonderflix/ui/skeletons.dart';

import '../support/pump_app.dart';
import '../support/social_fakes.dart';

class _SlowSocialApi extends FakeSocialApi {
  final gate = Completer<void>();

  @override
  Future<FriendsSnapshot> friends() async {
    await gate.future;
    return super.friends();
  }
}

Widget _header() => Scaffold(
  body: PanelHeader(title: 'Amici', closeTooltip: 'Chiudi', onClose: () {}),
);

void main() {
  testWidgets('sul desktop la testa ha la ✕', (t) async {
    await pumpApp(t, _header());
    expect(find.byTooltip('Chiudi'), findsOneWidget);
    expect(find.text('Amici'), findsOneWidget);
  });

  testWidgets('nello stretto la testa non ha la ✕', (t) async {
    await pumpApp(t, _header(), surfaceSize: const Size(390, 780));
    expect(find.byTooltip('Chiudi'), findsNothing);
    expect(find.text('Amici'), findsOneWidget);
  });

  testWidgets('in TV la testa non ha la ✕', (t) async {
    await pumpApp(t, _header(), tv: true, surfaceSize: const Size(960, 540));
    expect(find.byTooltip('Chiudi'), findsNothing);
    expect(find.text('Amici'), findsOneWidget);
  });

  testWidgets('sottotitolo e azioni stanno nella testa', (t) async {
    var closed = 0;
    await pumpApp(
      t,
      Scaffold(
        body: PanelHeader(
          title: 'Notifiche',
          subtitle: const Text('2 online'),
          actions: [TextButton(onPressed: () {}, child: const Text('Svuota'))],
          closeTooltip: 'Chiudi',
          onClose: () => closed++,
        ),
      ),
    );
    expect(find.text('2 online'), findsOneWidget);
    expect(find.text('Svuota'), findsOneWidget);
    await t.tap(find.byTooltip('Chiudi'));
    expect(closed, 1);
  });

  test('pannello largo 380', () {
    expect(ShellSidePanel.width, 380);
  });

  testWidgets('Amici mentre carica mostra le righe grigie', (t) async {
    final api = _SlowSocialApi();
    addTearDown(() {
      if (!api.gate.isCompleted) api.gate.complete();
    });
    await pumpApp(
      t,
      const Scaffold(body: SizedBox(width: 380, child: FriendsPanel())),
      overrides: socialTestOverrides(api),
    );
    await t.pump();
    expect(find.byType(PanelRowsSkeleton), findsOneWidget);
  });
}
