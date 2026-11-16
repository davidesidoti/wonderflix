import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/playback_rate.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('velocità scritte con la virgola', () {
    expect(playbackRates.map((r) => formatRate(r, ',')),
        ['0,75×', '1×', '1,25×', '1,5×', '2×']);
  });

  test('con il punto come separatore', () {
    expect(formatRate(1.25, '.'), '1.25×');
  });

  test('un titolo nuovo parte da 1×', () {
    expect(const PlayerViewState().rate, 1.0);
  });

  testWidgets('il menu ha le cinque velocità e la spunta sulla scelta',
      (tester) async {
    double? picked;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('it'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSpeedMenu(context,
                rate: 1.5, onSelected: (value) => picked = value),
            child: const Text('apri'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('1,5×'), findsOneWidget, reason: 'separatore del locale');
    for (final rate in playbackRates) {
      expect(find.byKey(ValueKey('rate-$rate')), findsOneWidget);
    }
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('rate-1.5')),
            matching: find.byIcon(Icons.check)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rate-2.0')));
    await tester.pumpAndSettle();
    expect(picked, 2.0);
  });
}
