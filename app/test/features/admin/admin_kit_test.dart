import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';

import '../../support/pump_app.dart';

void main() {
  test('lampColor: un colore per stato', () {
    expect(lampColor(LampState.ok), WfColors.online);
    expect(lampColor(LampState.attention), WfColors.gold);
    expect(lampColor(LampState.broken), WfColors.error);
    expect(lampColor(LampState.off), const Color(0xFF444444));
  });

  testWidgets('WfLamp: etichetta per i lettori di schermo, alone solo se acceso',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Column(children: [
          WfLamp(state: LampState.ok, label: 'Sonarr'),
          WfLamp(state: LampState.off, label: 'Radarr'),
        ]),
      ),
    );

    expect(find.bySemanticsLabel('Sonarr'), findsOneWidget);
    List<BoxShadow>? shadows(String label) {
      final box = tester.widget<DecoratedBox>(find.descendant(
        of: find.bySemanticsLabel(label),
        matching: find.byType(DecoratedBox),
      ));
      return (box.decoration as BoxDecoration).boxShadow;
    }

    expect(shadows('Sonarr'), isNotEmpty);
    expect(shadows('Sonarr')!.first.color, WfColors.online);
    expect(shadows('Radarr') ?? const [], isEmpty);
  });

  group('FilmStripBar', () {
    Future<int> filled(WidgetTester tester, double? progress) async {
      await pumpApp(
        tester,
        Scaffold(body: FilmStripBar(progress: progress)),
      );
      return find.byKey(const ValueKey('film-strip-filled')).evaluate().length;
    }

    testWidgets('46% = 5 fotogrammi su 12', (tester) async {
      expect(await filled(tester, 0.46), 5);
    });
    testWidgets('senza avanzamento tutti vuoti', (tester) async {
      expect(await filled(tester, null), 0);
    });
    testWidgets('oltre il 100% si ferma a 12', (tester) async {
      expect(await filled(tester, 1.5), 12);
    });
    testWidgets('negativo = 0', (tester) async {
      expect(await filled(tester, -1), 0);
    });
    testWidgets('NaN = 0', (tester) async {
      expect(await filled(tester, double.nan), 0);
    });
  });

  testWidgets('AdminSectionTitle: titolo e conteggio', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: AdminSectionTitle(title: 'In riproduzione', count: 2)),
    );

    expect(find.text('In riproduzione'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('AdminTabTitle: titolo, conteggio e azioni', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: AdminTabTitle(title: 'Utenti', count: 7, actions: [Text('Nuovo')]),
      ),
    );

    expect(find.text('Utenti'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Nuovo'), findsOneWidget);
  });

  testWidgets('AdminList: un separatore tra i figli', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: AdminList(children: [Text('a'), Text('b'), Text('c')]),
      ),
    );

    expect(find.byKey(const ValueKey('admin-list-divider')), findsNWidgets(2));
  });
}
