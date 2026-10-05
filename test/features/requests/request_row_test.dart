import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_row.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

  Future<List<String>> pumpRow(WidgetTester tester, MediaRequest request,
      {bool showRequester = false, Widget? trailing, bool tappable = true}) async {
    final taps = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: RequestRow(
          request: request,
          now: now,
          showRequester: showRequester,
          trailing: trailing,
          onTap: tappable ? () => taps.add('tap') : null,
        ),
      ),
    );
    return taps;
  }

  testWidgets('film: titolo, anno, chi l\'ha chiesto, quando, stato', (tester) async {
    final taps = await pumpRow(
      tester,
      testMediaRequest(title: 'Dune', year: 2021, requester: 'Garg', createdAt: fiveMinutesAgo),
      showRequester: true,
    );

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Film · chiesto da Garg · 5 min fa'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);

    await tester.tap(find.text('Dune (2021)'));
    expect(taps, ['tap']);
  });

  testWidgets('serie: le stagioni chieste; senza chi l\'ha chiesto', (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(
          title: 'Brothers',
          year: 2026,
          type: RequestMediaType.tv,
          seasons: const [2, 1],
          status: RequestStatus.downloading,
          progress: 0.45,
          createdAt: fiveMinutesAgo),
    );

    expect(find.text('Stagioni 1–2 · 5 min fa'), findsOneWidget);
    expect(find.text('In arrivo · 45%'), findsOneWidget);
  });

  testWidgets('senza il clic la riga non si apre (azione in corso)', (tester) async {
    final taps = await pumpRow(tester, testMediaRequest(title: 'Dune', year: 2021),
        tappable: false);

    await tester.tap(find.text('Dune (2021)'));
    await tester.pump();

    expect(taps, isEmpty);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('titolo che Seerr non ha dato; azioni al posto dello stato',
      (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(title: '', year: null, createdAt: fiveMinutesAgo),
      trailing: const Text('azioni'),
    );

    expect(find.text('Titolo non disponibile'), findsOneWidget);
    expect(find.text('azioni'), findsOneWidget);
    expect(find.text('In attesa'), findsNothing);
  });
}
