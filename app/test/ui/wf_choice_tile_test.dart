import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_choice_tile.dart';

import '../support/pump_app.dart';

void main() {
  Color? titleColor(WidgetTester t) =>
      t.widget<Text>(find.text('Sottotitoli')).style?.color;

  testWidgets('il riquadro scelto è oro e si annuncia scelto', (t) async {
    final handle = t.ensureSemantics();
    var taps = 0;
    await pumpApp(
      t,
      Scaffold(
        body: WfChoiceTile(
          title: 'Sottotitoli',
          description: 'Mancano o sono sbagliati',
          icon: LucideIcons.captions,
          selected: true,
          onTap: () => taps++,
        ),
      ),
    );
    expect(titleColor(t), WfColors.gold);
    expect(find.text('Mancano o sono sbagliati'), findsOneWidget);
    expect(
      t.getSemantics(find.byType(WfChoiceTile)),
      matchesSemantics(
        isSelected: true,
        hasSelectedState: true,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        label: 'Sottotitoli\nMancano o sono sbagliati',
      ),
    );
    await t.tap(find.text('Sottotitoli'));
    expect(taps, 1);

    await pumpApp(
      t,
      Scaffold(
        body: WfChoiceTile(title: 'Sottotitoli', selected: false, onTap: () {}),
      ),
    );
    expect(titleColor(t), WfColors.cream);
    handle.dispose();
  });

  testWidgets('TV: OK sul riquadro col focus lo sceglie', (t) async {
    var taps = 0;
    await pumpApp(
      t,
      Scaffold(
        body: WfChoiceTile(
          title: 'Sottotitoli',
          selected: false,
          autofocus: true,
          onTap: () => taps++,
        ),
      ),
      tv: true,
      surfaceSize: const Size(960, 540),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(taps, 1);
  });
}
