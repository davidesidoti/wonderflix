import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_rows_editing.dart';
import 'package:wonderflix/features/home/home_rows_editor.dart';

import '../../support/pump_app.dart';

void main() {
  late List<HomeRowKind> rows;
  late Set<HomeRowKind> off;
  late List<(HomeRowKind, int)> moves;
  late List<(HomeRowKind, bool)> toggles;

  setUp(() {
    rows = [HomeRowKind.resume, HomeRowKind.nextUp, HomeRowKind.upcomingSeries];
    off = {};
    moves = [];
    toggles = [];
  });

  /// Un elenco che applica davvero spostamenti e interruttori.
  Future<void> pumpEditor(WidgetTester tester,
      {bool lockUnavailable = true,
      Map<HomeRowKind, String> unavailable = const {}}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: HomeRowsEditor(
              lockUnavailable: lockUnavailable,
              entries: [
                for (final row in rows)
                  HomeRowsEditorEntry(
                      kind: row,
                      on: !off.contains(row),
                      unavailable: unavailable[row]),
              ],
              onMove: (row, to) => setState(() {
                moves.add((row, to));
                rows = moveRow(rows, row, to);
              }),
              onToggle: (row, on) => setState(() {
                toggles.add((row, on));
                on ? off.remove(row) : off.add(row);
              }),
            ),
          ),
        ),
      ),
    );
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('nomi, fonti e motivi', (tester) async {
    await pumpEditor(tester,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    expect(find.text('Serie in arrivo'), findsOneWidget);
    expect(find.text('da Sonarr'), findsOneWidget);
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
    expect(find.byIcon(LucideIcons.gripVertical), findsNWidgets(3));
  });

  testWidgets('una voce selezionata ha le frecce e si sposta', (tester) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('home-rows-up')), findsNothing);
    await tester.tap(find.text('Prossimi episodi'));
    await tester.pump();
    expect(find.byKey(const Key('home-rows-up')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-rows-down')));
    await tester.pump();
    expect(moves, [(HomeRowKind.nextUp, 2)]);
    expect(top(tester, 'Serie in arrivo'),
        lessThan(top(tester, 'Prossimi episodi')));
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-rows-down')))
            .onPressed,
        isNull,
        reason: 'resta selezionata ed è l\'ultima: non scende più');
  });

  testWidgets('da tastiera: Alt+↑ e Alt+↓ spostano la voce selezionata',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Serie in arrivo'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(moves, [(HomeRowKind.upcomingSeries, 1)]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(moves.last, (HomeRowKind.upcomingSeries, 2));
  });

  testWidgets('trascinando la maniglia', (tester) async {
    await pumpEditor(tester);
    final handle = find.byIcon(LucideIcons.gripVertical).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, isNotEmpty);
    expect(moves.last.$1, HomeRowKind.resume);
    expect(rows.first, isNot(HomeRowKind.resume));
  });

  testWidgets('l\'interruttore accende e spegne', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump();
    expect(toggles, [(HomeRowKind.nextUp, false)]);
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('home-rows-switch-nextUp')))
            .value,
        isFalse);
  });

  testWidgets('modo utente: una riga non disponibile è spenta e ferma, ma si '
      'sposta', (tester) async {
    await pumpEditor(tester,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    final toggle = tester.widget<Switch>(
        find.byKey(const Key('home-rows-switch-upcomingSeries')));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    await tester.tap(find.text('Serie in arrivo'));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-rows-up')))
            .onPressed,
        isNotNull);
  });

  testWidgets('modo admin: una riga non disponibile si accende lo stesso',
      (tester) async {
    off = {HomeRowKind.upcomingSeries};
    await pumpEditor(tester,
        lockUnavailable: false,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    await tester.tap(find.byKey(const Key('home-rows-switch-upcomingSeries')));
    await tester.pump();
    expect(toggles, [(HomeRowKind.upcomingSeries, true)]);
  });
}
