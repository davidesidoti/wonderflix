import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/features/player/player_time.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('tempo che resta e ora di fine', () {
    final l = lookupAppLocalizations(const Locale('it'));
    final now = DateTime(2026, 11, 16, 22, 51, 5);
    expect(
        formatRemaining(l,
            position: const Duration(minutes: 2, seconds: 5),
            duration: const Duration(minutes: 52),
            now: now),
        '−49:55 · finisce alle 23:41');
    expect(
        formatRemaining(l,
            position: const Duration(minutes: 2, seconds: 5),
            duration: const Duration(minutes: 52),
            now: now,
            rate: 2),
        '−49:55 · finisce alle 23:16');
    expect(
        formatRemaining(l,
            position: Duration.zero, duration: Duration.zero, now: now),
        isNull);
    expect(
        formatRemaining(l,
            position: const Duration(minutes: 60),
            duration: const Duration(minutes: 52),
            now: now),
        '−00:00 · finisce alle 22:51');
    expect(
        formatRemaining(l,
            position: Duration.zero,
            duration: const Duration(minutes: 2, seconds: 12),
            now: now,
            withEnd: false),
        '−02:12');
  });

  testWidgets("l'etichetta usa l'orologio del dispositivo", (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 16, 22, 51, 5)), () async {
      final engine = FakeVideoEngine();
      await pumpApp(
          tester,
          Scaffold(
              body: Column(children: [
            PositionLabel(engine: engine),
            RemainingLabel(engine: engine),
          ])));
      expect(find.byType(RemainingLabel), findsOneWidget);
      expect(find.text('−49:55 · finisce alle 23:41'), findsNothing,
          reason: 'durata ancora ignota: nessun testo');
      engine
        ..emitDuration(const Duration(minutes: 52))
        ..emitPosition(const Duration(minutes: 2, seconds: 5));
      await tester.pump(); // consegna gli eventi degli stream
      await tester.pump();
      expect(find.text('−49:55 · finisce alle 23:41'), findsOneWidget);
      expect(find.text('02:05'), findsOneWidget);
    });
  });
}
