import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/update/update_banner.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  Future<void> pumpBanner(WidgetTester t, Size size, {String? notes}) =>
      pumpApp(
          t,
          Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: UpdateBanner(
                      release: notes == null
                          ? testRelease()
                          : testRelease(notes: notes),
                      onRestart: () {},
                      onLater: () {}))),
          surfaceSize: size);

  const titleText = 'Aggiornamento pronto: WonderFlix 0.2.0';

  testWidgets('sotto 640 il banner va su due righe', (t) async {
    await pumpBanner(t, const Size(480, 800));
    final title = find.text(titleText);
    expect(t.getTopLeft(find.text('Riavvia ora')).dy,
        greaterThan(t.getBottomLeft(title).dy));
    expect(t.getTopLeft(find.text('Novità')).dx,
        lessThan(t.getTopLeft(find.text('Più tardi')).dx));
    expect(
        find.byWidgetPredicate((w) => w is WfButton && w.label == 'Riavvia ora'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a 360 i pulsanti vanno a capo senza sforare', (t) async {
    await pumpBanner(t, const Size(360, 800));
    expect(find.text('Riavvia ora'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('da 640 in su una riga sola', (t) async {
    await pumpBanner(t, const Size(1280, 800));
    expect(
        (t.getCenter(find.text('Riavvia ora')).dy -
                t.getCenter(find.text(titleText)).dy)
            .abs(),
        lessThan(12));
    expect(t.takeException(), isNull);
  });

  testWidgets('senza note niente "Novità", anche su due righe', (t) async {
    await pumpBanner(t, const Size(480, 800), notes: '');
    expect(find.text('Novità'), findsNothing);
    expect(find.text('Più tardi'), findsOneWidget);
    expect(find.text('Riavvia ora'), findsOneWidget);
  });
}
