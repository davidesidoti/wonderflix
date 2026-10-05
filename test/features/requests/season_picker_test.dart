import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/season_picker.dart';

import '../../support/pump_app.dart';

void main() {
  const seasons = [
    SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
    SeasonInfo(seasonNumber: 2, episodeCount: 1),
    SeasonInfo(seasonNumber: 3, episodeCount: 8, status: TitleStatus.pending),
    SeasonInfo(seasonNumber: 4, episodeCount: 8),
  ];

  Future<List<String>> pumpPicker(WidgetTester tester,
      {Set<int> selected = const {2, 4},
      bool enabled = true,
      List<SeasonInfo> list = seasons}) async {
    final taps = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: SeasonPicker(
          seasons: list,
          selected: selected,
          enabled: enabled,
          onToggle: (n) => taps.add('stagione $n'),
          onToggleAll: () => taps.add('tutte'),
        ),
      ),
    );
    return taps;
  }

  Checkbox checkboxOf(WidgetTester tester, String key) => tester.widget<Checkbox>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Checkbox)));

  testWidgets('righe con episodi e stato; "Tutte" in cima', (tester) async {
    await pumpPicker(tester, selected: const {2});

    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('Stagione 1 · 6 episodi'), findsOneWidget);
    expect(find.text('Stagione 2 · 1 episodio'), findsOneWidget);
    expect(find.text('Disponibile'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Da richiedere'), findsNWidgets(2));
    // Le stagioni già presenti o chieste sono segnate e bloccate.
    expect(checkboxOf(tester, 'season-1').value, isTrue);
    expect(checkboxOf(tester, 'season-1').onChanged, isNull);
    expect(checkboxOf(tester, 'season-2').value, isTrue);
    expect(checkboxOf(tester, 'season-4').value, isFalse);
    // Una sola su due scelta: "Tutte" a metà.
    expect(checkboxOf(tester, 'season-all').value, isNull);
  });

  testWidgets('clic: solo sulle stagioni da chiedere', (tester) async {
    final taps = await pumpPicker(tester);

    await tester.tap(find.text('Stagione 4 · 8 episodi'));
    await tester.tap(find.text('Stagione 1 · 6 episodi'));
    await tester.tap(find.text('Tutte'));

    expect(taps, ['stagione 4', 'tutte']);
    expect(checkboxOf(tester, 'season-all').value, isTrue);
  });

  testWidgets('spento durante l\'invio', (tester) async {
    final taps = await pumpPicker(tester, enabled: false);

    await tester.tap(find.text('Stagione 4 · 8 episodi'));
    await tester.tap(find.text('Tutte'));

    expect(taps, isEmpty);
  });

  testWidgets('una sola stagione da chiedere: niente "Tutte"', (tester) async {
    await pumpPicker(tester,
        selected: const {2}, list: seasons.take(2).toList());

    expect(find.text('Tutte'), findsNothing);
  });
}
