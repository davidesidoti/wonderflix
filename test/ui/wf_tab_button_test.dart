import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_tab_button.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('scheda scelta in crema con la riga oro; clic', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Row(children: [
          WfTabButton(label: 'Sessioni', selected: true, onTap: () => taps++),
          WfTabButton(label: 'Registro', selected: false, onTap: () {}),
        ]),
      ),
    );

    Text text(String label) => tester.widget<Text>(find.text(label));
    expect(text('Sessioni').style!.color, WfColors.cream);
    expect(text('Registro').style!.color, WfColors.creamMuted);

    await tester.tap(find.text('Sessioni'));
    expect(taps, 1);
  });
}
