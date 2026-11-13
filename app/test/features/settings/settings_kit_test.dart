import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/settings/settings_kit.dart';

import '../../support/pump_app.dart';

Widget _page(List<Widget> children) => Scaffold(
  body: SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);

void main() {
  group('SettingsSectionTitle', () {
    testWidgets('dice dove si salva, con l\'icona giusta', (tester) async {
      await pumpApp(
        tester,
        _page(const [
          SettingsSectionTitle(
            title: 'Riproduzione',
            scope: SettingsScope.device,
          ),
          SettingsSectionTitle(title: 'Home', scope: SettingsScope.account),
          SettingsSectionTitle(
            title: 'Sottotit',
            scope: SettingsScope.jellyfin,
          ),
          SettingsSectionTitle(title: 'Supporto'),
        ]),
      );
      expect(find.text('Riproduzione'), findsOneWidget);
      expect(find.text('Questo PC'), findsOneWidget);
      expect(find.text('Il tuo account'), findsOneWidget);
      expect(
        find.text('Il tuo account, in tutti i client Jellyfin'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.monitor), findsOneWidget);
      expect(find.byIcon(LucideIcons.cloud), findsNWidgets(2));
    });

    testWidgets('accetta una GlobalKey', (tester) async {
      final key = GlobalKey();
      await pumpApp(
        tester,
        _page([SettingsSectionTitle(key: key, title: 'X')]),
      );
      expect(key.currentContext, isNotNull);
    });

    testWidgets('nello stretto il titolo tiene una riga e a stringersi è '
        'il dove si salva', (tester) async {
      await pumpApp(
        tester,
        _page(const [
          SettingsSectionTitle(title: 'Home'),
          SettingsSectionTitle(
            title: 'Sottotit',
            scope: SettingsScope.jellyfin,
          ),
        ]),
        surfaceSize: const Size(330, 900),
      );
      expect(tester.takeException(), isNull);
      // Una riga come "Home": il titolo non è ridotto a metà della riga (nel
      // test il font è largo: 8 lettere sono 192 px, oltre la metà di 330).
      expect(
        tester.getSize(find.text('Sottotit')).height,
        tester.getSize(find.text('Home')).height,
      );
      expect(find.text('Il tuo account, in tutti i client Jellyfin'),
          findsOneWidget);
    });
  });

  group('SettingsRow', () {
    testWidgets('etichetta, aiuto e controllo; il tocco arriva a onTap', (
      tester,
    ) async {
      var taps = 0;
      await pumpApp(
        tester,
        _page([
          AdminList(
            children: [
              SettingsRow(
                label: 'Etichetta',
                hint: 'Un aiuto',
                trailing: const Text('Valore'),
                onTap: () => taps++,
              ),
            ],
          ),
        ]),
      );
      expect(find.text('Un aiuto'), findsOneWidget);
      expect(find.text('Valore'), findsOneWidget);
      await tester.tap(find.text('Etichetta'));
      expect(taps, 1);
    });

    testWidgets('la scia del tocco ha una tela anche in un AdminList', (
      tester,
    ) async {
      await pumpApp(
        tester,
        _page([
          AdminList(children: [SettingsRow(label: 'Riga', onTap: () {})]),
        ]),
      );
      expect(
        find.descendant(
          of: find.byType(SettingsRow),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
      final materials = tester.widgetList<Material>(
        find.ancestor(of: find.byType(InkWell), matching: find.byType(Material)),
      );
      expect(materials.first.type, MaterialType.transparency);
    });

    testWidgets('indent sposta l\'etichetta a destra', (tester) async {
      await pumpApp(
        tester,
        _page(const [
          SettingsRow(label: 'Sopra'),
          SettingsRow(label: 'Sotto', indent: 20),
        ]),
      );
      final dx =
          tester.getTopLeft(find.text('Sotto')).dx -
          tester.getTopLeft(find.text('Sopra')).dx;
      expect(dx, 20);
    });

    Future<void> pumpWide(WidgetTester tester, Size size) => pumpApp(
      tester,
      _page(const [
        SettingsRow(
          label: 'Etichetta',
          wideTrailing: true,
          trailing: Text('Controllo largo'),
        ),
      ]),
      surfaceSize: size,
    );

    testWidgets('wideTrailing: a destra nel largo', (tester) async {
      await pumpWide(tester, const Size(1440, 900));
      expect(
        tester.getTopLeft(find.text('Controllo largo')).dy,
        tester.getTopLeft(find.text('Etichetta')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Controllo largo')).dx,
        greaterThan(tester.getTopLeft(find.text('Etichetta')).dx),
      );
    });

    testWidgets('wideTrailing: sotto l\'etichetta nello stretto', (
      tester,
    ) async {
      await pumpWide(tester, const Size(500, 900));
      expect(
        tester.getTopLeft(find.text('Controllo largo')).dy,
        greaterThan(tester.getBottomLeft(find.text('Etichetta')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Controllo largo')).dx,
        tester.getTopLeft(find.text('Etichetta')).dx,
      );
    });
  });

  group('SettingsSwitchRow', () {
    testWidgets('la chiave sta sullo Switch e tutta la riga lo cambia', (
      tester,
    ) async {
      final values = <bool>[];
      await pumpApp(
        tester,
        _page([
          SettingsSwitchRow(
            key: const Key('s'),
            label: 'Interruttore',
            value: false,
            onChanged: values.add,
          ),
        ]),
      );
      expect(tester.widget<Switch>(find.byKey(const Key('s'))).value, isFalse);
      await tester.tap(find.text('Interruttore'));
      await tester.tap(find.byKey(const Key('s')));
      expect(values, [true, true]);
    });

    testWidgets('chi legge lo schermo trova un solo controllo', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        _page([
          SettingsSwitchRow(
            label: 'Interruttore',
            value: false,
            onChanged: (_) {},
          ),
        ]),
      );
      expect(
        tester.getSemantics(find.byType(SettingsSwitchRow)),
        isSemantics(
          label: 'Interruttore',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('onChanged nullo: riga spenta e senza risposta', (
      tester,
    ) async {
      await pumpApp(
        tester,
        _page(const [
          SettingsSwitchRow(
            key: Key('s'),
            label: 'Spento',
            hint: 'Dipende dall\'altro',
            value: true,
            onChanged: null,
          ),
        ]),
      );
      expect(
        tester.widget<Switch>(find.byKey(const Key('s'))).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byType(SettingsSwitchRow),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        0.45,
      );
      await tester.tap(find.text('Spento'));
      expect(tester.widget<Switch>(find.byKey(const Key('s'))).value, isTrue);
    });
  });

  group('SettingsDropdown', () {
    testWidgets('la chiave sta sul DropdownButton e sceglie', (tester) async {
      String? chosen;
      await pumpApp(
        tester,
        _page([
          SettingsDropdown<String>(
            key: const Key('d'),
            value: 'a',
            items: const [
              DropdownMenuItem(value: 'a', child: Text('Alfa')),
              DropdownMenuItem(value: 'b', child: Text('Beta')),
            ],
            onChanged: (v) => chosen = v,
          ),
        ]),
      );
      expect(find.byType(DropdownButtonHideUnderline), findsOneWidget);
      await tester.tap(find.byKey(const Key('d')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta').last);
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });
  });
}
