import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/space/space_gauge.dart';

import '../../support/pump_app.dart';

const _gb = 1000000000;

List<(String, int)> _parts(List<int> gbs) => [
      for (var i = 0; i < gbs.length; i++) ('P$i', gbs[i] * _gb),
    ];

int _flexOf(WidgetTester tester, Key key) =>
    tester.widget<Expanded>(find.byKey(key)).flex;

void main() {
  testWidgets('FiveSegmentsAndTheRestAreProportional', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: SpaceGauge(
          parts: _parts([440, 400, 560, 160, 60]),
          totalBytes: 2000 * _gb,
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      expect(
        _flexOf(tester, ValueKey('space-gauge-$i')),
        [440, 400, 560, 160, 60][i] * _gb,
      );
    }
    expect(_flexOf(tester, const ValueKey('space-gauge-rest')), 380 * _gb);
    final rest = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('space-gauge-rest')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(rest.color, WfColors.surfaceHigh);
    final first = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('space-gauge-0')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(first.color, spaceGaugeColors[0]);
    expect(tester.getSize(find.byKey(const ValueKey('space-gauge-bar'))).height, 22);
    // Un segmento senza figlio è alto 0 se la riga non lo stira.
    expect(tester.getSize(find.byKey(const ValueKey('space-gauge-0'))).height, 22);
    expect(find.text('P4 60,00 GB'), findsOneWidget);
  });

  testWidgets('WithoutATotalTheBarIsTheSumOfTheParts', (tester) async {
    await pumpApp(
      tester,
      Scaffold(body: SpaceGauge(parts: _parts([1, 1, 0, 0, 0]))),
    );

    expect(find.byKey(const ValueKey('space-gauge-rest')), findsNothing);
    expect(find.byKey(const ValueKey('space-gauge-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('space-gauge-2')), findsNothing);
  });

  testWidgets('AllZeroPartsGiveAnEmptyBarWithoutErrors', (tester) async {
    await pumpApp(
      tester,
      Scaffold(body: SpaceGauge(parts: _parts([0, 0, 0, 0, 0]))),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('space-gauge-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('space-gauge-0')), findsNothing);
  });
}
