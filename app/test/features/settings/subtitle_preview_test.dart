import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/settings/subtitle_preview.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

Future<void> _pumpSettings(
  WidgetTester tester,
  Size size,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpApp(
    tester,
    const Scaffold(body: SettingsScreen()),
    surfaceSize: size,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountAvailableProvider.overrideWithValue(false),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
        () => FakeSessionController(const SessionSignedIn(testUser)),
      ),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      ...homeSettingsOverrides(),
    ],
  );
  await tester.pump();
  await tester.pump();
}

final _text = find.byKey(const Key('subtitle-preview-text'));

double _fontSize(WidgetTester tester) =>
    tester.widget<Text>(_text).style!.fontSize!;

void main() {
  testWidgets(
    'la grandezza del testo segue la scala e l\'altezza del riquadro',
    (tester) async {
      Future<void> pump(double width, double scale) => pumpApp(
        tester,
        Center(
          child: SizedBox(
            width: width,
            child: SubtitlePreview(scale: scale),
          ),
        ),
      );

      await pump(640, 1.0);
      final height = tester.getSize(find.byType(AspectRatio)).height;
      expect(height, closeTo(360, 0.01), reason: '16:9');
      expect(_fontSize(tester), closeTo(55 * 360 / 720, 0.01));

      await pump(640, 0.45);
      expect(_fontSize(tester), closeTo(55 * 360 / 720 * 0.45, 0.01));

      await pump(300, 0.8);
      expect(_fontSize(tester), closeTo(55 * (300 * 9 / 16) / 720 * 0.8, 0.01));
      expect(find.text('Ci vediamo dopo il secondo tempo.'), findsOneWidget);
    },
  );

  testWidgets('cambiando la dimensione l\'anteprima si aggiorna', (
    tester,
  ) async {
    await _pumpSettings(tester, const Size(1440, 2400));
    final before = _fontSize(tester);
    await tester.tap(find.text('Molto piccoli'));
    await tester.pump();
    expect(_fontSize(tester), lessThan(before));
    final small = _fontSize(tester);
    await tester.tap(find.text('Molto grandi'));
    await tester.pump();
    expect(_fontSize(tester), greaterThan(small * 2));
  });

  Rect listOf(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.byKey(const Key('subtitle-mode')),
          matching: find.byType(AdminList),
        )
        .first,
  );

  testWidgets('nel largo l\'anteprima sta a destra dell\'elenco, larga 360', (
    tester,
  ) async {
    await _pumpSettings(tester, const Size(1440, 2400));
    expect(find.text('Anteprima dei sottotitoli'), findsOneWidget);
    final list = listOf(tester);
    final box = tester.getRect(find.byType(SubtitlePreview));
    expect(list.width, 1040 - 32 - 360);
    expect(box.width, 360);
    expect(box.left, list.right + 32);
    expect(box.top, lessThan(list.bottom));
  });

  testWidgets('in una finestra più stretta sta sotto l\'elenco, largo al più '
      '640', (tester) async {
    await _pumpSettings(tester, const Size(1100, 2400));
    final list = listOf(tester);
    final box = tester.getRect(find.byType(SubtitlePreview));
    expect(box.top, greaterThan(list.bottom));
    expect(box.left, list.left);
    expect(box.width, lessThanOrEqualTo(640));
    expect(box.width, greaterThan(300));
  });
}
