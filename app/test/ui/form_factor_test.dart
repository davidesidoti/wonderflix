import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/form_factor.dart';

import '../support/pump_app.dart';

/// Monta un widget che registra il [FormFactor] che vede.
Future<FormFactor Function()> _pump(
  WidgetTester tester,
  Size size, {
  bool? touch,
  bool withScope = true,
}) async {
  late FormFactor seen;
  final probe = Builder(
    builder: (context) {
      seen = FormFactor.of(context);
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    },
  );
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: withScope
          ? FormFactorScope(touchOverride: touch, child: probe)
          : probe,
    ),
  );
  return () => seen;
}

void main() {
  for (final (w, h, compact) in [
    (1023.0, 800.0, true),
    (1024.0, 800.0, false),
  ]) {
    testWidgets('stretto sotto 1024, largo da 1024: ${w}x$h', (tester) async {
      final ff = await _pump(tester, Size(w, h), touch: false);
      expect(ff().compact, compact);
    });
  }

  for (final (w, h, touch, phone) in [
    (390.0, 844.0, true, true),
    (844.0, 390.0, true, true),
    (768.0, 1024.0, true, false),
    (390.0, 844.0, false, false),
  ]) {
    testWidgets('telefono: tocco e lato corto sotto 600: ${w}x$h tocco=$touch',
        (tester) async {
      final ff = await _pump(tester, Size(w, h), touch: touch);
      expect(ff().phone, phone);
    });
  }

  testWidgets('il tocco segue l ultimo puntatore', (tester) async {
    final ff = await _pump(tester, const Size(800, 600));
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(ff().touch, isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    expect(ff().touch, isFalse);
  });

  testWidgets('senza scope: niente tocco, misura dalla MediaQuery', (
    tester,
  ) async {
    final ff = await _pump(tester, const Size(390, 844), withScope: false);
    expect(ff().touch, isFalse);
    expect(ff().compact, isTrue);
    expect(ff().phone, isFalse);
  });

  for (final touch in [false, true]) {
    testWidgets('pumpApp: tocco fisso a $touch', (tester) async {
      late FormFactor seen;
      final probe = Builder(builder: (context) {
        seen = FormFactor.of(context);
        return const SizedBox();
      });
      await pumpApp(tester, probe,
          surfaceSize: const Size(390, 844), touch: touch);
      // tester.tap è un tocco, ma l'override resta
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(seen.touch, touch);
      expect(seen.compact, isTrue); // la superficie vale anche per la MediaQuery
      expect(seen.phone, touch);
    });
  }
}
